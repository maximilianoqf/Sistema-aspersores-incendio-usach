function R = limite_caudal_aspersores(BD, parametros, config, casos)
%LIMITE_CAUDAL_ASPERSORES  Caudal MÍNIMO de operación de los aspersores ya
%   seleccionados que aún cumple el criterio de densidad de agua, y el punto
%   de operación (Q, HMT) que resulta de trabajar en ese mínimo.
%
%   R = limite_caudal_aspersores(BD, parametros, config)
%   R = limite_caudal_aspersores(BD, parametros, config, casos)
%
%   MOTIVACIÓN
%   ----------
%   La configuración ya está decidida (p. ej. 4×15-VAN en techo + 4×AQ-22 en
%   perímetro). El problema es encontrar una bomba: el caudal nominal es alto
%   para la HMT que se necesita. Como una boquilla de orificio fijo cumple
%
%         Q = K · sqrt(P)          (Q en L/min, P en bar)
%
%   NO se puede bajar el caudal manteniendo la presión: al bajar Q baja P, y
%   con P baja TAMBIÉN la HMT (la presión de boquilla es el término dominante
%   de la HMT). Es decir, el punto de operación se mueve completo hacia abajo.
%
%   Esta función calcula CUÁNTO se puede bajar el caudal por aspersor sin
%   incumplir el criterio de densidad de `calcular_fuego`, respetando además:
%       (1) DENSIDAD    : densidad_zona = n·Q_asp / A_zona ≥ densidad_req
%                         ⇒ Q_asp ≥ densidad_req · A_zona / n
%       (2) P_MIN BOQUILLA: por debajo de P_min_bar la boquilla no atomiza/
%                         distribuye bien ⇒ Q_asp ≥ K·sqrt(P_min)
%       (3) RADIO/COBERTURA: a menor presión el radio de alcance cae como
%                         r(P) = r_nom·(P/P_nom)^alpha; debe mantenerse la
%                         cobertura geométrica n·π·r² ≥ A_zona·factor_cob.
%
%   El caudal mínimo por aspersor es el MAYOR de los tres pisos. A partir de
%   él se obtiene P_op = (Q_min/K)², y con la MISMA cadena hidráulica del
%   iterador se calculan el caudal total y la HMT resultantes, que definen
%   el objetivo de bomba (SIN usar la BD de bombas).
%
%   ENTRADAS
%   --------
%   BD         : estructura de cargar_BD (usa BD.aspersores, BD.tuberias).
%   parametros : mismos parámetros que el iterador (áreas, densidad requerida
%                por defecto, factores, cotas, longitudes, K's...).
%                Campos nuevos opcionales:
%                  .exp_radio_presion        (alpha, def 0.5)  @CITA
%                  .factor_traslape_cobertura (def 0.85)
%   config     : misma interfaz del iterador:
%                  .asp_techo_id, .asp_perim_id, .n_techo, .n_perim,
%                  .DN_principal, .material_principal, .DN_ramal, .material_ramal
%   casos      : (opcional) struct array de casos de fuego para calcular_fuego
%                (campos .nombre,.w0_kgm2,.sav_1m,.delta_m,.Mf,.Mx,.viento_ms...).
%                Si se omite, se usa un único "caso" con las densidades
%                requeridas que ya trae `parametros`.
%
%   SALIDA
%   ------
%   R : struct array (uno por caso) con el detalle por zona y el punto de
%       operación mínimo vs. nominal. Además imprime un reporte por consola.
%
%   Ver también: ITERAR_CONFIGURACIONES, CALCULAR_FUEGO.

    % =========================================================
    % 0. Aspersores seleccionados y sus rangos operativos
    % =========================================================
    at = BD.aspersores(strcmp(BD.aspersores.ID, config.asp_techo_id), :);
    ap = BD.aspersores(strcmp(BD.aspersores.ID, config.asp_perim_id), :);
    if isempty(at) || isempty(ap)
        error('limite_caudal_aspersores:asp', ...
               'Aspersor de techo o perímetro no existe en BD.');
    end

    zonaT = extraer_aspersor(at, config.n_techo);
    zonaP = extraer_aspersor(ap, config.n_perim);

    % Áreas de referencia
    A_techo = parametros.area_techo_m2;
    A_perim = obtener(parametros, 'area_perimetro_m2', ...
              obtener(parametros,'perimetro_m',27.2) * ...
              obtener(parametros,'ancho_franja_m',2.5));

    factor_cob = obtener(parametros, 'factor_traslape_cobertura', 0.85);
    alpha      = obtener(parametros, 'exp_radio_presion', 0.5);  % r∝P^alpha @CITA

    % =========================================================
    % 1. Casos de densidad requerida
    % =========================================================
    if nargin < 4 || isempty(casos)
        c1 = struct('nombre','(densidades de parametros)', ...
                    'densidad_techo_Lmin_m2', parametros.densidad_techo_Lmin_m2, ...
                    'densidad_perimetro_Lmin_m2', parametros.densidad_perimetro_Lmin_m2, ...
                    't_operacion_min', obtener(parametros,'t_operacion_min',NaN), ...
                    'es_fuego', false);
        lista_casos = c1;
    else
        lista_casos = repmat(struct('nombre','','densidad_techo_Lmin_m2',0, ...
                       'densidad_perimetro_Lmin_m2',0,'t_operacion_min',0, ...
                       'es_fuego',true), 1, numel(casos));
        for k = 1:numel(casos)
            fr = calcular_fuego(casos(k));
            lista_casos(k).nombre = fr.nombre;
            lista_casos(k).densidad_techo_Lmin_m2     = fr.densidad_techo_Lmin_m2;
            lista_casos(k).densidad_perimetro_Lmin_m2 = fr.densidad_perimetro_Lmin_m2;
            lista_casos(k).t_operacion_min = fr.t_operacion_min;
            lista_casos(k).es_fuego = true;
        end
    end

    % =========================================================
    % 2. Barrido por caso
    % =========================================================
    R = repmat(estructura_vacia(), 1, numel(lista_casos));
    for k = 1:numel(lista_casos)
        ck = lista_casos(k);

        limT = limite_una_zona(zonaT, ck.densidad_techo_Lmin_m2, ...
                               A_techo, config.n_techo, factor_cob, alpha);
        limP = limite_una_zona(zonaP, ck.densidad_perimetro_Lmin_m2, ...
                               A_perim, config.n_perim, factor_cob, alpha);

        % Punto de operación MÍNIMO (cada zona en su Q_asp_min / P_op)
        edo_min = estado_hidraulico(BD, parametros, config, ...
                    limT.Q_asp_op, limT.P_op_bar, limP.Q_asp_op, limP.P_op_bar);
        % Punto de operación NOMINAL (Q_nom / P_nom), para comparar
        edo_nom = estado_hidraulico(BD, parametros, config, ...
                    zonaT.Q_nom, zonaT.P_nom, zonaP.Q_nom, zonaP.P_nom);

        % Volumen de estanque (caudal nominal de operación × t_op)
        fsv = obtener(parametros,'factor_seg_volumen',1.0);
        top = ck.t_operacion_min;
        R(k).V_estanque_min_m3 = edo_min.Q_total_nom_Lmin * top/1000 * fsv;
        R(k).V_estanque_nom_m3 = edo_nom.Q_total_nom_Lmin * top/1000 * fsv;

        R(k).nombre   = ck.nombre;
        R(k).es_fuego = ck.es_fuego;
        R(k).dens_req_techo = ck.densidad_techo_Lmin_m2;
        R(k).dens_req_perim = ck.densidad_perimetro_Lmin_m2;
        R(k).t_operacion_min = top;
        R(k).techo = limT;
        R(k).perim = limP;
        R(k).min   = edo_min;
        R(k).nom   = edo_nom;
        R(k).factible = limT.factible && limP.factible && ...
                        edo_min.v_princ <= obtener(parametros,'v_max_principal',2.5)*1.0001;
    end

    imprimir_reporte(R, zonaT, zonaP, config, alpha);
end


% =====================================================================
%  LÍMITE DE UNA ZONA (los 3 pisos + factibilidad + radio operativo)
% =====================================================================
function L = limite_una_zona(z, densidad_req, A_zona, n, factor_cob, alpha)
    K = z.K;  Pnom = z.P_nom;  Pmin = z.P_min;  Pmax = z.P_max;
    Qnom = z.Q_nom;  r_nom = z.Radio;

    % (1) Piso por DENSIDAD
    Q_dens = densidad_req * A_zona / n;

    % (2) Piso por PRESIÓN MÍNIMA de la boquilla
    Q_pmin = K * sqrt(Pmin);

    % (3) Piso por RADIO/COBERTURA: r debe cubrir n·π·r² ≥ A·factor_cob.
    %     Radio requerido -> presión requerida -> caudal requerido.
    r_req = sqrt(A_zona * factor_cob / (n * pi));
    if r_req <= r_nom
        P_rad  = Pnom * (r_req / r_nom)^(1/alpha);   % presión que da r_req
        Q_rad  = K * sqrt(P_rad);
        cobertura_nominal_ok = true;
    else
        % Ni al nominal se alcanza la cobertura pedida: no es un piso de
        % reducción, es una falla de cobertura de la propia configuración.
        Q_rad  = Qnom;         % no permite bajar del nominal
        P_rad  = Pnom;
        cobertura_nominal_ok = false;
    end

    % Caudal mínimo de operación = el MAYOR de los tres pisos
    pisos   = [Q_dens, Q_pmin, Q_rad];
    nombres = {'densidad','P_min boquilla','radio/cobertura'};
    [Q_min, idx] = max(pisos);
    Q_min = min(Q_min, Qnom);                 % nunca por encima del nominal
    P_op  = (Q_min / K)^2;
    r_op  = r_nom * (P_op / Pnom)^alpha;

    % Factibilidad: la densidad NO debe exigir más presión que P_max, y la
    % cobertura al nominal debe existir. Si Q_dens > Q_nom, la selección
    % actual ni siquiera cumple densidad al nominal.
    P_dens_bar = (Q_dens / K)^2;
    cumple_dens_nominal = (Q_dens <= Qnom + 1e-9);
    dentro_de_rango     = (P_op <= Pmax + 1e-9);
    factible = cumple_dens_nominal && dentro_de_rango && cobertura_nominal_ok;

    L = struct();
    L.modelo   = z.modelo;
    L.n        = n;
    L.K        = K;
    L.Q_nom    = Qnom;   L.P_nom = Pnom;   L.r_nom = r_nom;
    L.P_min    = Pmin;   L.P_max = Pmax;
    L.Q_dens   = Q_dens;      L.P_dens_bar = P_dens_bar;
    L.Q_pmin   = Q_pmin;
    L.Q_rad    = Q_rad;       L.r_req = r_req;
    L.Q_asp_op = Q_min;       L.P_op_bar = P_op;   L.r_op = r_op;
    L.restriccion_activa = nombres{idx};
    L.reduccion_Q_pct = 100 * (1 - Q_min / Qnom);
    L.reduccion_P_pct = 100 * (1 - P_op / Pnom);
    L.densidad_op = n * Q_min / A_zona;         % densidad realmente aplicada
    L.factible = factible;
    L.cumple_dens_nominal = cumple_dens_nominal;
    L.cobertura_nominal_ok = cobertura_nominal_ok;
end


% =====================================================================
%  ESTADO HIDRÁULICO para un punto de operación dado
%  (misma cadena hidráulica del iterador, parametrizada por el caudal y la
%   presión de operación de cada zona)
% =====================================================================
function E = estado_hidraulico(BD, parametros, config, ...
                               q_asp_techo, P_techo_bar, q_asp_perim, P_perim_bar)

    tub_princ = fila_tuberia(BD, config.DN_principal, config.material_principal);
    tub_ramal = fila_tuberia(BD, config.DN_ramal,     config.material_ramal);
    if isempty(tub_princ) || isempty(tub_ramal)
        error('limite_caudal_aspersores:tub','Tubería no existe en BD.');
    end

    n_t = config.n_techo;  n_p = config.n_perim;

    % --- Caudales por zona (nominal de operación) ---
    Q_techo_tot = n_t * q_asp_techo;
    Q_perim_tot = n_p * q_asp_perim;

    modo = lower(obtener(parametros,'modo_activacion','simultaneo'));
    switch modo
        case 'simultaneo'
            Q_princ_nom = Q_techo_tot + Q_perim_tot;
            act_techo = Q_techo_tot > 0;  act_perim = Q_perim_tot > 0;
        case 'zonal'
            Q_princ_nom = max(Q_techo_tot, Q_perim_tot);
            act_techo = (Q_techo_tot >= Q_perim_tot);
            act_perim = ~act_techo;
        otherwise
            error('limite_caudal_aspersores:modo','modo_activacion no reconocido: %s',modo);
    end

    f = obtener(parametros,'factor_seg_caudal',1.10);
    Q_princ_m3s = (Q_princ_nom * f) / 60000;
    q_mont_m3s  = (q_asp_techo * f) / 60000;   % un montante = un aspersor
    q_rper_m3s  = (q_asp_perim * f) / 60000;   % un ramal perim = un aspersor

    % --- Geometría hidráulica ---
    D_princ = tub_princ.D_interno_mm/1000;  A_princ = pi*D_princ^2/4;
    D_ramal = tub_ramal.D_interno_mm/1000;  A_ramal = pi*D_ramal^2/4;

    v_princ   = Q_princ_m3s / A_princ;
    v_r_techo = q_mont_m3s  / A_ramal;
    v_r_perim = q_rper_m3s  / A_ramal;

    g   = obtener(parametros,'g',9.81);
    h_f = @(Q,C,D,L) 10.674 * max(Q,1e-12)^1.852 / (C^1.852 * D^4.871) * L;

    % Longitudes / cotas / conexión (mismos defaults del iterador)
    L_adu    = obtener(parametros,'L_aduccion_m', obtener(parametros,'L_principal_m',5));
    L_anillo = obtener(parametros,'perimetro_m',27.2);
    if obtener(parametros,'anillo_cerrado',true)
        L_crit = L_adu + L_anillo/2;
    else
        L_crit = L_adu + L_anillo;
    end
    L_mont = obtener(parametros,'L_montante_techo_m',2.1);
    L_rper = obtener(parametros,'L_ramal_perim_unit_m',2.5);
    z_agua = obtener(parametros,'z_agua_estanque_m',0);
    z_techo = L_mont;  z_perim = 0;

    D_con = obtener(parametros,'conexion_D_int_mm',15.8)/1000;
    C_con = obtener(parametros,'conexion_C_HW',140);
    L_con = obtener(parametros,'conexion_L_m',0.3);
    A_con = pi*D_con^2/4;
    K_tee = obtener(parametros,'K_tee',1.8);
    K_codo= obtener(parametros,'K_codo',0.9);
    K_con = obtener(parametros,'n_bujes',2) * obtener(parametros,'K_buje',0.4);
    h_con = @(q) h_f(q,C_con,D_con,L_con) + K_con*(q/A_con)^2/(2*g);

    fl = obtener(parametros,'factor_localizadas',1.25);

    % --- Pérdidas ---
    h_principal = h_f(Q_princ_m3s, tub_princ.C_HW, D_princ, L_crit);
    h_r_techo = h_f(q_mont_m3s, tub_ramal.C_HW, D_ramal, L_mont) ...
              + K_tee*v_r_techo^2/(2*g) + h_con(q_mont_m3s);
    h_r_perim = h_f(q_rper_m3s, tub_ramal.C_HW, D_ramal, L_rper) ...
              + (K_tee+K_codo)*v_r_perim^2/(2*g) + h_con(q_rper_m3s);

    % --- HMT por zona ---
    HMT_techo = (z_techo - z_agua) + fl*h_principal + h_r_techo + P_techo_bar*10.197;
    HMT_perim = (z_perim - z_agua) + fl*h_principal + h_r_perim + P_perim_bar*10.197;

    HMTs = [HMT_techo, HMT_perim];
    HMTs([~act_techo, ~act_perim]) = -inf;
    [HMT, idx] = max(HMTs);
    zonas = {'Techo','Perímetro'};

    E = struct();
    E.Q_total_nom_Lmin = Q_princ_nom;
    E.Q_total_dis_Lmin = Q_princ_nom * f;
    E.Q_total_dis_m3h  = Q_princ_nom * f * 60/1000;
    E.v_princ = v_princ;
    E.v_ramal_max = max(v_r_techo, v_r_perim);
    E.h_principal = h_principal;
    E.HMT_techo = HMT_techo;
    E.HMT_perim = HMT_perim;
    E.HMT_m = HMT;
    E.HMT_bar = HMT/10.197;
    E.zona_critica = zonas{idx};
end


% =====================================================================
%  REPORTE
% =====================================================================
function imprimir_reporte(R, zonaT, zonaP, config, alpha)
    L = 78;
    fprintf('%s\n', repmat('=',1,L));
    fprintf('LÍMITE DE CAUDAL DE LOS ASPERSORES SELECCIONADOS (criterio de densidad)\n');
    fprintf('%s\n', repmat('=',1,L));
    fprintf('Techo   : %d × %s   K=%.2f  Q_nom=%.2f L/min @ %.2f bar  (P_min=%.1f, P_max=%.1f)\n', ...
            config.n_techo, zonaT.modelo, zonaT.K, zonaT.Q_nom, zonaT.P_nom, zonaT.P_min, zonaT.P_max);
    fprintf('Perímetro: %d × %s   K=%.2f  Q_nom=%.2f L/min @ %.2f bar  (P_min=%.1f, P_max=%.1f)\n', ...
            config.n_perim, zonaP.modelo, zonaP.K, zonaP.Q_nom, zonaP.P_nom, zonaP.P_min, zonaP.P_max);
    fprintf('Modelo radio-presión: r(P)=r_nom·(P/P_nom)^%.2f  (alpha @CITA)\n', alpha);
    fprintf('%s\n', repmat('-',1,L));

    for k = 1:numel(R)
        r = R(k);
        fprintf('\nCASO: %s\n', r.nombre);
        fprintf('  Densidad requerida  →  techo %.2f  |  perímetro %.2f  [L/min/m²]\n', ...
                r.dens_req_techo, r.dens_req_perim);
        imprimir_zona('Techo    ', r.techo);
        imprimir_zona('Perímetro', r.perim);

        fprintf('  %s\n', repmat('.',1,L-2));
        fprintf('  PUNTO DE OPERACIÓN     %12s %14s %12s\n','NOMINAL','MÍNIMO','Δ');
        fprintf('    Caudal total     [L/min]  %10.1f %14.1f %11.1f%%\n', ...
                r.nom.Q_total_dis_Lmin, r.min.Q_total_dis_Lmin, ...
                -100*(1 - r.min.Q_total_dis_Lmin/r.nom.Q_total_dis_Lmin));
        fprintf('    Caudal total     [m³/h ]  %10.2f %14.2f\n', ...
                r.nom.Q_total_dis_m3h, r.min.Q_total_dis_m3h);
        fprintf('    HMT              [m.c.a]  %10.2f %14.2f %11.1f%%\n', ...
                r.nom.HMT_m, r.min.HMT_m, -100*(1 - r.min.HMT_m/r.nom.HMT_m));
        fprintf('    HMT              [bar  ]  %10.2f %14.2f\n', ...
                r.nom.HMT_bar, r.min.HMT_bar);
        if ~isnan(r.V_estanque_min_m3)
            fprintf('    Volumen estanque [m³   ]  %10.2f %14.2f\n', ...
                    r.V_estanque_nom_m3, r.V_estanque_min_m3);
        end
        fprintf('    Velocidad ppal   [m/s  ]  %10.2f %14.2f\n', ...
                r.nom.v_princ, r.min.v_princ);

        if r.factible
            fprintf('  >> OBJETIVO DE BOMBA (mínimo):  Q ≈ %.1f L/min (%.2f m³/h)  a  HMT ≈ %.1f m (%.2f bar)\n', ...
                    r.min.Q_total_dis_Lmin, r.min.Q_total_dis_m3h, r.min.HMT_m, r.min.HMT_bar);
        else
            fprintf('  >> CASO NO FACTIBLE con esta selección: revisar advertencias por zona.\n');
        end
    end
    fprintf('\n%s\n', repmat('=',1,L));
    fprintf('Nota: el "mínimo" es el caudal más bajo que aún cumple densidad, P_min y\n');
    fprintf('cobertura. Bajar de ahí incumpliría el criterio. No se consultó BD_Bombas.\n');
    fprintf('%s\n', repmat('=',1,L));
end

function imprimir_zona(etq, z)
    fprintf('  [%s]  Q_asp: nom %.2f → min %.2f L/min (-%.1f%%)  |  P: nom %.2f → %.2f bar  |  r_op %.2f m\n', ...
            etq, z.Q_nom, z.Q_asp_op, z.reduccion_Q_pct, z.P_nom, z.P_op_bar, z.r_op);
    fprintf('             pisos → densidad %.2f | P_min %.2f | radio %.2f  ⇒ manda: %s\n', ...
            z.Q_dens, z.Q_pmin, z.Q_rad, z.restriccion_activa);
    if ~z.cumple_dens_nominal
        fprintf('             ⚠ la densidad requerida NO se cumple ni al caudal nominal (falta caudal/aspersores).\n');
    end
    if ~z.cobertura_nominal_ok
        fprintf('             ⚠ cobertura geométrica insuficiente incluso al nominal (radio muy chico).\n');
    end
    if ~z.factible
        fprintf('             ⚠ zona NO factible: P_op=%.2f bar fuera de rango [%.1f, %.1f].\n', ...
                z.P_op_bar, z.P_min, z.P_max);
    end
end


% =====================================================================
%  HELPERS
% =====================================================================
function z = extraer_aspersor(fila, n)
    z = struct();
    z.modelo = char(string(fila.Modelo));
    z.K      = fila.K_factor;
    z.Q_nom  = fila.Q_nominal_Lmin;
    z.P_nom  = fila.P_nominal_bar;
    z.P_min  = fila.P_min_bar;
    z.P_max  = fila.P_max_bar;
    z.Radio  = fila.Radio_m;
    z.n      = n;
end

function t = fila_tuberia(BD, DN, material)
    t = BD.tuberias(BD.tuberias.DN_mm == DN & strcmp(BD.tuberias.Material, material), :);
end

function E = estructura_vacia()
    E = struct('nombre','','es_fuego',false,'dens_req_techo',NaN, ...
        'dens_req_perim',NaN,'t_operacion_min',NaN,'techo',struct(), ...
        'perim',struct(),'min',struct(),'nom',struct(), ...
        'V_estanque_min_m3',NaN,'V_estanque_nom_m3',NaN,'factible',false);
end
