function resultados = iterar_configuraciones(BD, parametros, iteracion)
%ITERAR_CONFIGURACIONES  Recorre el espacio de diseño y evalúa cada combinación.
%
%   resultados = iterar_configuraciones(BD, parametros, iteracion)
%
%   SALIDA:
%       resultados.viables      : table con las configuraciones viables,
%                                 ordenadas por score (mejor primero).
%       resultados.n_evaluadas  : nº total de combinaciones recorridas.
%
%   El score se calcula según iteracion.criterio_optimo:
%       'costo' | 'potencia' | 'agua' | 'compuesto'
%
%   MODELO HIDRÁULICO (trazado real del proyecto — mismo modelo que
%   verificacion_hidraulica_bomba.py):
%     • Principal: aducción estanque→anillo + ANILLO perimetral cerrado
%       alrededor de la vivienda (longitud = perímetro del contorno).
%       Camino crítico de fricción = aducción + medio anillo, con todo el
%       caudal de diseño (conservador: el anillo alimenta por ambos lados).
%     • Techo: n_techo MONTANTES verticales DN ramal EN PARALELO (uno por
%       aspersor, derivados del anillo con TEE); cota aspersor = L montante.
%     • Perímetro: n_perim ramales horizontales DN ramal EN PARALELO
%       (TEE + codo 90°), aspersor a nivel de terreno.
%     • Conexión al aspersor: niple 1/2" + bujes reductores (K explícitos).
%     • factor_localizadas mayora SOLO la fricción de la principal; las
%       pérdidas locales de los ramales van explícitas por coeficiente K.
%     • Altura estática POR ZONA: cota aspersor − cota espejo de agua.
%     • parametros.usar_nebulizadores = false excluye la zona de ventanas
%       (caudal, HMT, costo y cobertura).
%
%   IMPLEMENTACIÓN
%   --------------
%   Barrido inline optimizado para el espacio de diseño:
%     • las bases de datos se pre-extraen a arreglos planos una sola vez,
%       evitando indexar tablas (strcmp / ==) en cada iteración;
%     • los bucles se ordenan de lo más restrictivo a lo más interno, con
%       poda temprana (densidad y cobertura cortan antes de tocar diámetros
%       y bombas);
%     • solo se acumulan las configuraciones viables (no se construye la
%       tabla completa, que no se usa aguas abajo).

    % =====================================================================
    %  1. PRE-EXTRACCIÓN DE LAS BASES DE DATOS  (una sola vez)
    % =====================================================================
    asp = BD.aspersores;
    [AT_Q, AT_R, AT_P, AT_precio, AT_modelo] = extraer_aspersores(asp, 'Techo');
    [AP_Q, ~,   AP_P, AP_precio, AP_modelo]  = extraer_aspersores(asp, 'Perímetro');
    [AV_Q, ~,   AV_P, AV_precio, AV_modelo]  = extraer_aspersores(asp, 'Ventana');

    nT = numel(AT_Q);  nP = numel(AP_Q);  nV = numel(AV_Q);

    % --- Tuberías: tabla de búsqueda (material × DN) -> [D_int, C_HW, precio] ---
    mats   = iteracion.materiales;
    DNp    = iteracion.DN_principal;
    DNr    = iteracion.DN_ramal;
    [Pdint, Pc, Pprecio, Pok] = lookup_tuberias(BD.tuberias, mats, DNp);
    [Rdint, Rc, Rprecio, Rok] = lookup_tuberias(BD.tuberias, mats, DNr);

    % --- Bombas: arreglos por modelo + preprocesado de curvas ---
    pumps = preparar_pumps(BD.bombas);

    % =====================================================================
    %  2. PARÁMETROS ESCALARES (acceso local, sin tocar el struct en el bucle)
    % =====================================================================
    nt_min = iteracion.n_techo_min;      nt_max = iteracion.n_techo_max;
    np_min = iteracion.n_perimetro_min;  np_max = iteracion.n_perimetro_max;
    nDp = numel(DNp);  nDr = numel(DNr);  nM = numel(mats);

    area_t = parametros.area_techo_m2;
    area_p = parametros.area_perimetro_m2;
    dens_t_req = parametros.densidad_techo_Lmin_m2;
    dens_p_req = parametros.densidad_perimetro_Lmin_m2;
    n_vent     = parametros.n_ventanas;

    % --- Trazado real: aducción + anillo perimetral cerrado ---
    L_adu    = obtener(parametros, 'L_aduccion_m', obtener(parametros, 'L_principal_m', 5));
    L_anillo = obtener(parametros, 'perimetro_m', 27.2);   % el anillo sigue el contorno
    if obtener(parametros, 'anillo_cerrado', true)
        L_crit = L_adu + L_anillo/2;   % alimenta por ambos lados → camino crítico
    else
        L_crit = L_adu + L_anillo;
    end
    L_mont = obtener(parametros, 'L_montante_techo_m', 2.1);    % montante POR aspersor de techo
    L_rper = obtener(parametros, 'L_ramal_perim_unit_m', 2.5);  % ramal POR aspersor de perímetro
    Lrv    = obtener(parametros, 'L_ramal_vent_m', 0);          % mangueras del kit (solo costo)

    % --- Cotas → altura estática por zona (z_aspersor − z_agua) ---
    z_agua  = obtener(parametros, 'z_agua_estanque_m', 0);
    z_techo = L_mont;                    % boquilla en la punta del montante
    z_perim = 0;
    z_vent  = obtener(parametros, 'z_aspersor_vent_m', 1.5);

    fseg  = parametros.factor_seg_caudal;
    fl    = parametros.factor_localizadas;
    fsv   = parametros.factor_seg_volumen;
    vmaxP = parametros.v_max_principal;
    vmaxR = parametros.v_max_ramal;
    t_op  = parametros.t_operacion_min;
    t_op_h = t_op / 60;
    costo_kWh = parametros.costo_kWh_CLP;
    modo = lower(parametros.modo_activacion);

    g   = obtener(parametros, 'g',   9.81);
    rho = obtener(parametros, 'rho', 1000);
    factor_cob = obtener(parametros, 'factor_traslape_cobertura', 0.85);
    h_kit_vent = obtener(parametros, 'h_kit_vent_m', 0);

    % --- Conexión reducida al aspersor (niple 1/2" + bujes) y accesorios K ---
    D_con  = obtener(parametros, 'conexion_D_int_mm', 15.8) / 1000;
    C_con  = obtener(parametros, 'conexion_C_HW', 140);
    L_con  = obtener(parametros, 'conexion_L_m', 0.3);
    A_con  = pi*D_con^2/4;
    K_tee  = obtener(parametros, 'K_tee', 1.8);     % TEE derivación anillo→ramal
    K_codo = obtener(parametros, 'K_codo', 0.9);    % codo 90° del ramal perimetral
    K_conex = obtener(parametros, 'n_bujes', 2) * obtener(parametros, 'K_buje', 0.4);

    % --- Nebulizadores de ventana: opcionales ---
    usar_neb = obtener(parametros, 'usar_nebulizadores', true);
    if ~usar_neb
        n_vent = 0;  Lrv = 0;  h_kit_vent = 0;
        AV_Q = 0;  AV_P = 0;  AV_precio = 0;  AV_modelo = {'(sin nebulizadores)'};
        nV = 1;
    end

    N_max_par   = parametros.n_bombas_paralelo_max;
    HP_max_par  = parametros.HP_max_paralelo;
    costo_acc   = parametros.costo_accesorios_paralelo;
    fa          = obtener(parametros, 'factor_arranque', 1.0);  % margen de potencia instalada

    % Combinaciones de bombas (1 unidad o varias en paralelo, iguales o mixtas)
    cache_bombas = bombas_construir_cache(pumps, N_max_par, HP_max_par, costo_acc);

    % Caudal de ventana (n_vent fijo) por modelo: pre-calculado
    AV_Qtot = AV_Q * n_vent;                 % L/min por modelo de nebulizador

    n_total = nT*nP*nV * (nt_max-nt_min+1) * (np_max-np_min+1) * nDp*nDr*nM;
    fprintf('  Espacio de búsqueda: ~%d combinaciones\n', n_total);

    % =====================================================================
    %  3. BUFFER DE VIABLES  (struct array con crecimiento geométrico)
    % =====================================================================
    plantilla = plantilla_fila();
    cap = 8192;
    buf = repmat(plantilla, cap, 1);
    nv = 0;

    % =====================================================================
    %  4. BARRIDO CON PODA TEMPRANA
    % =====================================================================
    for i_t = 1:nT
      Qn_t = AT_Q(i_t);  cobf_t = pi*AT_R(i_t)^2;  Hasp_t = AT_P(i_t)*10.197;
      for n_t = nt_min:nt_max
        Q_techo = n_t * Qn_t;
        % --- PODA: densidad y cobertura de techo (solo dependen de i_t, n_t) ---
        if Q_techo/area_t < dens_t_req,        continue; end
        if n_t*cobf_t   < area_t*factor_cob,   continue; end

        for i_p = 1:nP
          Qn_p = AP_Q(i_p);  Hasp_p = AP_P(i_p)*10.197;
          for n_p = np_min:np_max
            Q_perim = n_p * Qn_p;
            % --- PODA: densidad de perímetro (depende de i_p, n_p) ---
            if Q_perim/area_p < dens_p_req,    continue; end

            for i_v = 1:nV
              Q_vent = AV_Qtot(i_v);  Hasp_v = AV_P(i_v)*10.197;

              % --- Caudales por tramo según modo ---
              switch modo
                case 'simultaneo'
                  Q_princ_nom = Q_techo + Q_perim + Q_vent;
                  Qr_techo_nom = Q_techo;  Qr_perim_nom = Q_perim;
                  Qr_vent_nom  = Q_vent;
                  zona_crit = 'Simultáneo';
                case 'zonal'
                  [Q_princ_nom, ic] = max([Q_techo, Q_perim, Q_vent]);
                  zonas = {'Techo','Perímetro','Ventana'};
                  zona_crit = zonas{ic};
                  Qr_techo_nom = Q_techo*(ic==1);
                  Qr_perim_nom = Q_perim*(ic==2);
                  Qr_vent_nom  = Q_vent *(ic==3);
                otherwise
                  error('iterar_configuraciones:modo', ...
                        'Modo de activación no reconocido: %s', modo);
              end

              Q_princ   = Q_princ_nom * fseg;        % caudal de diseño
              Q_princ_m3s = Q_princ / 60000;
              Qr_techo_m3s = Qr_techo_nom * fseg / 60000;
              Qr_perim_m3s = Qr_perim_nom * fseg / 60000;

              for i_m = 1:nM
                precio_t = AT_precio(i_t);  precio_p = AP_precio(i_p);  precio_v = AV_precio(i_v);
                costo_asp = n_t*precio_t + n_p*precio_p + n_vent*precio_v;

                for i_dp = 1:nDp
                  if ~Pok(i_m,i_dp), continue; end
                  Dp = Pdint(i_m,i_dp)/1000;
                  A_p = pi*Dp^2/4;
                  v_princ = Q_princ_m3s / A_p;
                  if v_princ > vmaxP, continue; end           % PODA velocidad principal
                  Cp = Pc(i_m,i_dp);
                  h_principal = hazen(Q_princ_m3s, Cp, Dp, L_crit);

                  for i_dr = 1:nDr
                    if ~Rok(i_m,i_dr), continue; end
                    Dr = Rdint(i_m,i_dr)/1000;
                    A_r = pi*Dr^2/4;
                    % Ramales EN PARALELO: cada montante/ramal lleva el caudal
                    % de UN solo aspersor (no el de la zona completa).
                    q_mont_m3s = Qr_techo_m3s / max(n_t,1);
                    q_rper_m3s = Qr_perim_m3s / max(n_p,1);
                    v_r_techo = q_mont_m3s / A_r;
                    v_r_perim = q_rper_m3s / A_r;
                    v_ramal = max(v_r_techo, v_r_perim);
                    if v_ramal > vmaxR, continue; end          % PODA velocidad ramal

                    Cr = Rc(i_m,i_dr);
                    % Rama = fricción del tubo + accesorios (K) + conexión 1/2"
                    h_r_techo = hazen(q_mont_m3s, Cr, Dr, L_mont) ...
                              + K_tee * v_r_techo^2/(2*g) ...
                              + perdida_conexion(q_mont_m3s, C_con, D_con, L_con, A_con, K_conex, g);
                    h_r_perim = hazen(q_rper_m3s, Cr, Dr, L_rper) ...
                              + (K_tee + K_codo) * v_r_perim^2/(2*g) ...
                              + perdida_conexion(q_rper_m3s, C_con, D_con, L_con, A_con, K_conex, g);

                    % --- HMT por zona: estática propia + fricción principal
                    %     mayorada + pérdidas de la rama + presión aspersor ---
                    h_r_vec   = [h_r_techo, h_r_perim, h_kit_vent];
                    Hasp_vec  = [Hasp_t, Hasp_p, Hasp_v];
                    Hest_vec  = [z_techo, z_perim, z_vent] - z_agua;
                    HMT_rama  = Hest_vec + fl*h_principal + h_r_vec + Hasp_vec;
                    HMT_rama([Qr_techo_nom, Qr_perim_nom, Qr_vent_nom] <= 0) = -inf;
                    [HMT, idx] = max(HMT_rama);
                    H_aspersor = Hasp_vec(idx);
                    H_est_crit = Hest_vec(idx);
                    h_friccion = h_principal + h_r_vec(idx);
                    h_localiz  = (fl-1)*h_principal;  % solo principal (ramas: K explícito)

                    % --- Selección del grupo de bombeo (iguales o mixtas) ---
                    sel = seleccionar_grupo_bombas(pumps, cache_bombas, ...
                        Q_princ, HMT, H_est_crit, H_aspersor, fa, rho, g);
                    if ~sel.ok, continue; end
                    Q_oper = sel.Q_oper;  H_oper = sel.H_oper;

                    % --- Estanque, costos y energía ---
                    % Costo: anillo COMPLETO + aducción (la mitad solo aplica a
                    % la fricción); ramales = un montante/ramal por aspersor.
                    V_est = (Q_princ_nom * t_op / 1000) * fsv;
                    costo_tub = (L_adu + L_anillo)*Pprecio(i_m,i_dp) + ...
                                (n_t*L_mont + n_p*L_rper + Lrv)*Rprecio(i_m,i_dr);
                    costo_total = costo_asp + costo_tub + sel.costo;
                    costo_op = sel.P_kW_cons * t_op_h * costo_kWh;
                    HP_req = sel.HP_req;

                    % --- Registrar fila viable ---
                    nv = nv + 1;
                    if nv > cap, cap = cap*2; buf(cap) = plantilla; end
                    f = plantilla;
                    f.config_id        = nv;
                    f.asp_techo        = AT_modelo(i_t);
                    f.n_techo          = n_t;
                    f.asp_perim        = AP_modelo(i_p);
                    f.n_perim          = n_p;
                    f.asp_vent         = AV_modelo(i_v);
                    f.n_vent           = n_vent;
                    f.material_princ   = mats(i_m);
                    f.DN_princ_mm      = DNp(i_dp);
                    f.material_ramal   = mats(i_m);
                    f.DN_ramal_mm      = DNr(i_dr);
                    f.zona_critica     = {zona_crit};
                    f.Q_techo_Lmin     = Q_techo;
                    f.Q_perim_Lmin     = Q_perim;
                    f.Q_vent_Lmin      = Q_vent;
                    f.Q_diseno_Lmin    = Q_princ;
                    f.densidad_techo   = Q_techo/area_t;
                    f.densidad_perim   = Q_perim/area_p;
                    f.v_principal_ms   = v_princ;
                    f.v_ramal_ms       = v_ramal;
                    f.h_friccion_m     = h_friccion;
                    f.h_localizada_m   = h_localiz;
                    f.H_estatica_m     = H_est_crit;
                    f.H_aspersor_m     = H_aspersor;
                    f.HMT_m            = HMT;
                    f.bomba_modelo     = {sel.modelo_str};
                    f.bomba_marca      = {sel.marca_str};
                    f.bomba_lista      = {strjoin(sel.lista, ';')};
                    f.n_bombas         = sel.n;
                    f.P_HP             = sel.PHP;
                    f.P_kW             = sel.PkW;
                    f.Q_oper_Lmin      = Q_oper;
                    f.H_oper_m         = H_oper;
                    f.V_estanque_m3    = V_est;
                    f.costo_aspersores = costo_asp;
                    f.costo_tuberia    = costo_tub;
                    f.costo_bomba      = sel.costo;
                    f.costo_total_CLP  = costo_total;
                    f.score            = NaN;
                    f.eficiencia       = sel.eficiencia;
                    f.costo_op_evento_CLP = costo_op;
                    f.HP_requerido     = HP_req;
                    buf(nv) = f;

                  end % i_dr
                end % i_dp
              end % i_m
            end % i_v
          end % n_p
        end % i_p
      end % n_t
    end % i_t

    % =====================================================================
    %  5. TABLA DE VIABLES + SCORE
    % =====================================================================
    if nv == 0
        viables = plantilla_tabla_vacia();
    else
        viables = struct2table(buf(1:nv));
        viables = calcular_score(viables, iteracion);
    end

    resultados.viables     = viables;
    resultados.n_evaluadas = n_total;
end


% =====================================================================
%  HELPERS
% =====================================================================
function h = hazen(Q_m3s, C, D_m, L_m)
    h = 10.674 * max(Q_m3s,1e-12)^1.852 / (C^1.852 * D_m^4.871) * L_m;
end

function h = perdida_conexion(q_m3s, C, D_m, L_m, A_m2, K_total, g)
%PERDIDA_CONEXION  Niple 1/2" al aspersor: fricción del tramo + bujes
%   reductores (K), evaluados con el caudal de UN aspersor.
    v = q_m3s / A_m2;
    h = hazen(q_m3s, C, D_m, L_m) + K_total * v^2 / (2*g);
end

function [Q, R, P, precio, modelo] = extraer_aspersores(asp, zona)
    mask = strcmp(asp.Zona_uso, zona);
    Q = asp.Q_nominal_Lmin(mask);
    R = asp.Radio_m(mask);
    P = asp.P_nominal_bar(mask);
    precio = asp.Precio_CLP(mask);
    modelo = asp.Modelo(mask);
end

function [Dint, C, precio, ok] = lookup_tuberias(tub, mats, DNs)
    % Devuelve matrices (nMat × nDN) con D_interno, C_HW, precio y validez.
    nM = numel(mats);  nD = numel(DNs);
    Dint = zeros(nM,nD);  C = zeros(nM,nD);  precio = zeros(nM,nD);  ok = false(nM,nD);
    for im = 1:nM
        for id = 1:nD
            sel = tub.DN_mm == DNs(id) & strcmp(tub.Material, mats{im});
            if any(sel)
                k = find(sel,1);
                Dint(im,id)   = tub.D_interno_mm(k);
                C(im,id)      = tub.C_HW(k);
                precio(im,id) = tub.Precio_CLP_m(k);
                ok(im,id)     = true;
            end
        end
    end
end

function viables = calcular_score(viables, iteracion)
    norm_costo    = normaliza(viables.costo_total_CLP);
    norm_potencia = normaliza(viables.P_HP);
    norm_agua     = normaliza(viables.V_estanque_m3);
    switch iteracion.criterio_optimo
        case 'costo',     s = norm_costo;
        case 'potencia',  s = norm_potencia;
        case 'agua',      s = norm_agua;
        case 'compuesto', s = iteracion.pesos.costo*norm_costo + ...
                              iteracion.pesos.potencia*norm_potencia + ...
                              iteracion.pesos.agua*norm_agua;
        otherwise,        s = norm_costo;
    end
    viables.score = s;
    viables = sortrows(viables, 'score');
end

function y = normaliza(x)
    y = (x - min(x)) / max(eps, max(x) - min(x));
end

function f = plantilla_fila()
    % Campos en el MISMO orden que las columnas de la tabla de viables.
    f.config_id = 0;
    f.asp_techo = {''};
    f.n_techo = 0;
    f.asp_perim = {''};
    f.n_perim = 0;
    f.asp_vent = {''};
    f.n_vent = 0;
    f.material_princ = {''};
    f.DN_princ_mm = 0;
    f.material_ramal = {''};
    f.DN_ramal_mm = 0;
    f.zona_critica = {''};
    f.Q_techo_Lmin = NaN;
    f.Q_perim_Lmin = NaN;
    f.Q_vent_Lmin = NaN;
    f.Q_diseno_Lmin = NaN;
    f.densidad_techo = NaN;
    f.densidad_perim = NaN;
    f.v_principal_ms = NaN;
    f.v_ramal_ms = NaN;
    f.h_friccion_m = NaN;
    f.h_localizada_m = NaN;
    f.H_estatica_m = NaN;
    f.H_aspersor_m = NaN;
    f.HMT_m = NaN;
    f.bomba_modelo = {''};
    f.bomba_marca = {''};
    f.bomba_lista = {''};
    f.n_bombas = NaN;
    f.P_HP = NaN;
    f.P_kW = NaN;
    f.Q_oper_Lmin = NaN;
    f.H_oper_m = NaN;
    f.V_estanque_m3 = NaN;
    f.costo_aspersores = NaN;
    f.costo_tuberia = NaN;
    f.costo_bomba = NaN;
    f.costo_total_CLP = NaN;
    f.score = NaN;
    f.eficiencia = NaN;
    f.costo_op_evento_CLP = NaN;
    f.HP_requerido = NaN;
end

function T = plantilla_tabla_vacia()
    T = struct2table(plantilla_fila(), 'AsArray', true);
    T(1,:) = [];
end
