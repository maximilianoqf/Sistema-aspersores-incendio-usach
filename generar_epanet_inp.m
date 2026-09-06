function generar_epanet_inp(optima, parametros, BD, ruta_archivo)
%GENERAR_EPANET_INP  Escribe un archivo .inp de EPANET con la configuracion
%   optima del iterador.
%
%   generar_epanet_inp(optima, parametros, BD, ruta_archivo)
%
%   TOPOLOGIA (trazado real del proyecto, el mismo de iterar_configuraciones
%   y verificacion_hidraulica_bomba.py):
%     - Aduccion DN principal de L_aduccion_m desde el estanque/grupo de
%       bombeo hasta el ANILLO perimetral cerrado DN principal, que sigue
%       el contorno de la vivienda a nivel de terreno.
%     - En cada estacion del anillo se deriva con TEE un montante vertical
%       DN ramal de L_montante_techo_m (aspersor de techo en la punta, a
%       cota +L_montante) y un ramal horizontal DN ramal de
%       L_ramal_perim_unit_m (aspersor perimetral a cota 0). Si
%       n_techo == n_perim ambas derivaciones comparten la misma estacion.
%     - Nebulizadores de ventana opcionales (optima.n_vent puede ser 0),
%       alimentados desde la estacion mas cercana del anillo.
%
%   Las posiciones de las estaciones salen del MISMO motor parametrico que
%   el layout (geometria_vivienda, 'distribuir_perimetro' con offset 0),
%   de modo que el .inp, las figuras y los parametros hidraulicos quedan
%   siempre consistentes con las dimensiones ingresadas en la interfaz.
%
%   La conexion reducida de 1/2" al aspersor (niple + bujes) no se modela
%   como tramo propio: su perdida esta cuantificada en el modelo analitico
%   y aqui se omite, por lo que el .inp queda levemente optimista en ese
%   termino. Las TEE y codos de las derivaciones van como perdida menor.

    % =========================================================
    %  1. Validaciones y datos
    % =========================================================
    asp_techo = BD.aspersores(strcmp(BD.aspersores.Modelo, optima.asp_techo{1}), :);
    asp_perim = BD.aspersores(strcmp(BD.aspersores.Modelo, optima.asp_perim{1}), :);
    usar_vent = optima.n_vent > 0;   % nebulizadores opcionales
    if usar_vent
        asp_vent = BD.aspersores(strcmp(BD.aspersores.Modelo, optima.asp_vent{1}), :);
    else
        asp_vent = [];
    end
    if isempty(asp_techo) || isempty(asp_perim) || (usar_vent && isempty(asp_vent))
        error('Modelo de aspersor no encontrado en BD.');
    end

    % Bombas por unidad física (el grupo puede ser mixto: "A;A;B").
    % optima es una fila de tabla -> usar VariableNames, no isfield.
    if ismember('bomba_lista', optima.Properties.VariableNames) && ~isempty(optima.bomba_lista{1})
        modelos_unidad = strsplit(optima.bomba_lista{1}, ';');
    else
        modelos_unidad = repmat(optima.bomba_modelo(1), 1, optima.n_bombas);
    end

    tub_princ = BD.tuberias(BD.tuberias.DN_mm == optima.DN_princ_mm & ...
                            strcmp(BD.tuberias.Material, optima.material_princ{1}), :);
    tub_ramal = BD.tuberias(BD.tuberias.DN_mm == optima.DN_ramal_mm & ...
                            strcmp(BD.tuberias.Material, optima.material_ramal{1}), :);
    if isempty(tub_princ) || isempty(tub_ramal)
        error('Tuberia no encontrada en BD.');
    end

    % Coeficientes de emisor en unidades EPANET: K_e = K_factor / sqrt(10.197)
    Ke_techo = asp_techo.K_factor / sqrt(10.197);
    Ke_perim = asp_perim.K_factor / sqrt(10.197);
    if usar_vent
        Ke_vent = asp_vent.K_factor / sqrt(10.197);
    else
        Ke_vent = 0;
    end

    % Curva de cada bomba del grupo (por unidad física)
    N = numel(modelos_unidad);
    Qb_u = cell(1,N);  Hb_u = cell(1,N);
    for i = 1:N
        k = find(strcmp(BD.bombas.Modelo, modelos_unidad{i}), 1);
        if isempty(k)
            error('Modelo de bomba "%s" no encontrado en BD.', modelos_unidad{i});
        end
        Qb_u{i} = BD.bombas.Q_curva{k};
        Hb_u{i} = BD.bombas.H_curva{k};
    end

    % =========================================================
    %  2. Geometria parametrica: anillo perimetral + derivaciones
    % =========================================================
    parametros = geometria_vivienda('asegurar', parametros);
    geo = geometria_vivienda('construir', parametros);
    contorno = geo.contorno;

    % Longitudes y accesorios del trazado (mismos parametros que el iterador)
    L_adu  = obtener(parametros, 'L_aduccion_m', obtener(parametros, 'L_principal_m', 5));
    L_mont = obtener(parametros, 'L_montante_techo_m', 2.1);
    L_rper = obtener(parametros, 'L_ramal_perim_unit_m', 2.5);
    K_tee  = obtener(parametros, 'K_tee', 1.8);
    K_codo = obtener(parametros, 'K_codo', 0.9);
    z_vent_inp = obtener(parametros, 'z_aspersor_vent_m', 1.5);

    % Estaciones sobre el anillo (offset 0 = sobre el contorno)
    st_techo = geometria_vivienda('distribuir_perimetro', geo, optima.n_techo, 0);
    st_perim = geometria_vivienda('distribuir_perimetro', geo, optima.n_perim, 0);

    % Alimentacion del anillo por el oriente (mismo criterio que
    % graficar_red_hidraulica.m: punto del contorno mas cercano al estanque)
    q_este = [max(contorno(:,1)), (min(contorno(:,2)) + max(contorno(:,2)))/2];
    [p_feed, nrm_feed] = proyectar_contorno(contorno, q_este);

    % Estaciones ordenadas por abscisa curvilinea, fusionando coincidentes.
    % La estacion 1 (JA1) es la que recibe la aduccion.
    [est, iJA_techo, iJA_perim] = construir_estaciones(contorno, p_feed, st_techo, st_perim);
    m_est = size(est.xy, 1);

    if usar_vent
        pos_vent = geo.ventanas_centros;
    else
        pos_vent = zeros(0,2);   % sin nebulizadores: no se generan nodos JV
    end
    n_vent_eff = size(pos_vent, 1);
    iJA_vent = zeros(n_vent_eff, 1);   % cada nebulizador cuelga de la estacion mas cercana
    for i = 1:n_vent_eff
        d2 = sum((est.xy - pos_vent(i,:)).^2, 2);
        [~, iJA_vent(i)] = min(d2);
    end

    % Coordenadas de dibujo. El montante es vertical (coincide con su
    % estacion en planta): se desplaza hacia adentro solo para que el nodo
    % JT no tape al nodo JA en el mapa de EPANET.
    pos_techo = zeros(optima.n_techo, 2);
    for i = 1:optima.n_techo
        [~, nrm] = proyectar_contorno(contorno, st_techo(i,:));
        pos_techo(i,:) = st_techo(i,:) - 0.6*nrm;
    end
    % El aspersor perimetral queda al final de su ramal, perpendicular al anillo
    pos_perim = zeros(optima.n_perim, 2);
    for i = 1:optima.n_perim
        [~, nrm] = proyectar_contorno(contorno, st_perim(i,:));
        pos_perim(i,:) = st_perim(i,:) + L_rper*nrm;
    end

    % =========================================================
    %  3. Nodos del grupo de bombeo (al oriente, sobre la aduccion)
    % =========================================================
    dirF  = nrm_feed;                      % normal exterior en la alimentacion
    perpF = [-dirF(2), dirF(1)];
    L_dib = max(L_adu, 3.0);               % separacion solo para el dibujo

    coords.J_MAN_D    = p_feed + 0.40*L_dib*dirF;
    coords.J_MAN_S    = p_feed + 0.80*L_dib*dirF;
    coords.R_ESTANQUE = p_feed + (L_dib + 1.0)*dirF;
    xy_BD = zeros(N,2);  xy_BS = zeros(N,2);
    for i = 1:N
        if N == 1, off = 0; else, off = -0.5 + (i-1)/(N-1); end
        xy_BD(i,:) = p_feed + 0.52*L_dib*dirF + off*perpF;
        xy_BS(i,:) = p_feed + 0.68*L_dib*dirF + off*perpF;
    end

    % Bounding-box de la franja (etiqueta) y de todo el dibujo (BACKDROP)
    franja = geometria_vivienda('expandir', contorno, parametros.ancho_franja_m);
    bb = [min(franja(:,1)) min(franja(:,2)) max(franja(:,1)) max(franja(:,2))];
    xy_todos = [franja; est.xy; pos_techo; pos_perim; pos_vent; ...
                coords.R_ESTANQUE; coords.J_MAN_S; coords.J_MAN_D; xy_BS; xy_BD];
    bb_all = [min(xy_todos(:,1)) min(xy_todos(:,2)) max(xy_todos(:,1)) max(xy_todos(:,2))];

    % =========================================================
    %  4. Abrir archivo y escribir
    % =========================================================
    fid = fopen(ruta_archivo, 'w');
    if fid < 0
        error('No se pudo abrir el archivo para escritura: %s', ruta_archivo);
    end

    % ----- [TITLE] -----
    fprintf(fid, '[TITLE]\n');
    fprintf(fid, 'Sistema contra incendios forestales - Vivienda WUI\n');
    fprintf(fid, 'Generado automaticamente desde MATLAB (%s)\n', datestr(now,'yyyy-mm-dd HH:MM'));
    fprintf(fid, 'Vivienda %s  %.1f x %.1f m  (area techo %.1f m2, perimetro %.1f m)\n', ...
            upper(parametros.disp.forma), parametros.disp.largo_m, parametros.disp.ancho_m, ...
            geo.area_techo_m2, geo.perimetro_m);
    fprintf(fid, 'Trazado: aduccion %.1f m + anillo perimetral cerrado %.1f m (%d estaciones)\n', ...
            L_adu, est.L_total, m_est);
    fprintf(fid, 'Configuracion optima:\n');
    fprintf(fid, '  %d aspersores %s en techo (K=%.3f LPM/sqrt(bar)), montante %.1f m c/u\n', ...
            optima.n_techo, optima.asp_techo{1}, asp_techo.K_factor, L_mont);
    fprintf(fid, '  %d aspersores %s en perimetro (K=%.3f LPM/sqrt(bar)), ramal %.1f m c/u\n', ...
            optima.n_perim, optima.asp_perim{1}, asp_perim.K_factor, L_rper);
    if usar_vent
        fprintf(fid, '  %d nebulizadores %s en ventanas (K=%.3f LPM/sqrt(bar))\n', ...
                optima.n_vent, optima.asp_vent{1}, asp_vent.K_factor);
    else
        fprintf(fid, '  Sin nebulizadores de ventana (opcion desactivada)\n');
    end
    fprintf(fid, '  Grupo de bombeo: %s  (%d uds., %.1f HP total)\n', ...
            optima.bomba_modelo{1}, optima.n_bombas, optima.P_HP);
    fprintf(fid, '  Tuberia principal: %s DN%d (D_int=%.1f mm)\n', ...
            optima.material_princ{1}, optima.DN_princ_mm, tub_princ.D_interno_mm);
    fprintf(fid, '  Ramales: %s DN%d (D_int=%.1f mm)\n', ...
            optima.material_ramal{1}, optima.DN_ramal_mm, tub_ramal.D_interno_mm);
    fprintf(fid, 'Caudal: %.0f L/min  HMT: %.1f m  V_estanque: %.1f m3\n\n', ...
            optima.Q_diseno_Lmin, optima.HMT_m, optima.V_estanque_m3);

    % ----- [JUNCTIONS] -----
    % Cotas coherentes con el modelo hidraulico: anillo y perimetro a nivel
    % de terreno, techo en la punta del montante, ventanas a su altura.
    fprintf(fid, '[JUNCTIONS]\n');
    fprintf(fid, ';ID            Elev   Demand\n');
    fprintf(fid, 'J_MAN_S        0      0\n');
    for i = 1:N
        fprintf(fid, 'J_B%d_S         0      0\n', i);
        fprintf(fid, 'J_B%d_D         0      0\n', i);
    end
    fprintf(fid, 'J_MAN_D        0      0\n');
    for k = 1:m_est
        fprintf(fid, 'JA%-3d          0      0\n', k);
    end
    for i = 1:optima.n_techo
        fprintf(fid, 'JT%-2d           %.1f    0\n', i, L_mont);
    end
    for i = 1:optima.n_perim
        fprintf(fid, 'JP%-2d           0.0    0\n', i);
    end
    for i = 1:n_vent_eff
        fprintf(fid, 'JV%-2d           %.1f    0\n', i, z_vent_inp);
    end
    fprintf(fid, '\n');

    % ----- [RESERVOIRS] -----
    fprintf(fid, '[RESERVOIRS]\n;ID         Head\n');
    fprintf(fid, 'R_ESTANQUE     0\n\n');

    fprintf(fid, '[TANKS]\n\n');

    % ----- [PIPES] -----
    fprintf(fid, '[PIPES]\n');
    fprintf(fid, ';ID         Node1         Node2         Length  Diam   Rough.  MLoss   Status\n');

    D_p = tub_princ.D_interno_mm; C_p = tub_princ.C_HW;
    D_r = tub_ramal.D_interno_mm; C_r = tub_ramal.C_HW;

    % Succion corta y colectores del grupo de bombeo (sus perdidas van como
    % coeficientes de perdida menor; la aduccion de proyecto es P_ADUC)
    fprintf(fid, 'P_ASP       R_ESTANQUE    J_MAN_S       1.0     %.1f   %d     0.5     Open\n', D_p, C_p);
    for i = 1:N
        fprintf(fid, 'P_SUC%d      J_MAN_S       J_B%d_S        0.5     %.1f   %d     0.3     Open\n', i, i, D_p, C_p);
        fprintf(fid, 'P_DESC%d     J_B%d_D        J_MAN_D       0.8     %.1f   %d     2.2     Open\n', i, i, D_p, C_p);
    end
    % Aduccion DN principal: grupo de bombeo -> anillo (L_aduccion_m)
    fprintf(fid, 'P_ADUC      J_MAN_D       JA1           %.2f    %.1f   %d     0.5     Open\n', L_adu, D_p, C_p);

    % Anillo perimetral CERRADO: tramos entre estaciones consecutivas con
    % sus longitudes reales sobre el contorno (suman el perimetro completo).
    % Los codos del anillo no se modelan uno a uno (en el modelo analitico
    % los cubre factor_localizadas).
    fprintf(fid, ';-- ANILLO perimetral DN%d --\n', optima.DN_princ_mm);
    if m_est >= 2
        for k = 1:m_est
            k2 = mod(k, m_est) + 1;
            Lk = est.s(k2) - est.s(k);
            if Lk <= 0, Lk = Lk + est.L_total; end
            fprintf(fid, 'P_AN%-3d     JA%-3d         JA%-3d         %.2f    %.1f   %d     0       Open\n', ...
                    k, k, k2, Lk, D_p, C_p);
        end
    end

    % Montantes de techo: TEE en la estacion, sube L_mont hasta el aspersor
    fprintf(fid, ';-- MONTANTES techo DN%d (TEE en el anillo, K=%.1f) --\n', optima.DN_ramal_mm, K_tee);
    for i = 1:optima.n_techo
        fprintf(fid, 'P_MT_%-2d     JA%-3d         JT%-2d          %.2f    %.1f   %d     %.1f     Open\n', ...
                i, iJA_techo(i), i, L_mont, D_r, C_r, K_tee);
    end

    % Ramales perimetrales: TEE en la estacion + codo 90 al final
    fprintf(fid, ';-- RAMALES perimetro DN%d (TEE + codo 90, K=%.1f) --\n', optima.DN_ramal_mm, K_tee + K_codo);
    for i = 1:optima.n_perim
        fprintf(fid, 'P_RP_%-2d     JA%-3d         JP%-2d          %.2f    %.1f   %d     %.1f     Open\n', ...
                i, iJA_perim(i), i, L_rper, D_r, C_r, K_tee + K_codo);
    end

    % Ramal VENTANAS: desde la estacion mas cercana del anillo (opcional)
    if usar_vent
        fprintf(fid, ';-- RAMALES ventanas (desde la estacion mas cercana) --\n');
        for i = 1:n_vent_eff
            L_i = max(0.5, norm(pos_vent(i,:) - est.xy(iJA_vent(i),:)));
            fprintf(fid, 'P_RV_%-2d     JA%-3d         JV%-2d          %.2f    %.1f   %d     %.1f     Open\n', ...
                    i, iJA_vent(i), i, L_i, D_r, C_r, K_tee);
        end
    end
    fprintf(fid, '\n');

    % ----- [PUMPS] -----  (cada unidad usa su propia curva)
    fprintf(fid, '[PUMPS]\n;ID         Node1     Node2     Parameters\n');
    for i = 1:N
        fprintf(fid, 'BOMBA%d      J_B%d_S     J_B%d_D     HEAD CURVA_PUMP%d\n', i, i, i, i);
    end
    fprintf(fid, '\n');

    fprintf(fid, '[VALVES]\n\n[TAGS]\n\n[DEMANDS]\n\n[STATUS]\n\n[PATTERNS]\n\n');

    % ----- [CURVES] -----  (una curva por unidad física)
    fprintf(fid, '[CURVES]\n;ID         X(Q L/min)   Y(H m)\n');
    for i = 1:N
        fprintf(fid, ';PUMP: Curva caracteristica BOMBA%d = %s\n', i, modelos_unidad{i});
        Qc = Qb_u{i};  Hc = Hb_u{i};
        for k = 1:numel(Qc)
            fprintf(fid, 'CURVA_PUMP%d  %-12.1f %.1f\n', i, Qc(k), Hc(k));
        end
    end
    fprintf(fid, '\n[CONTROLS]\n\n[RULES]\n\n');

    fprintf(fid, '[ENERGY]\n');
    fprintf(fid, 'Global Efficiency            %d\n', max(1, round(optima.eficiencia*100)));
    fprintf(fid, 'Global Price                 %.4f\n', parametros.costo_kWh_CLP/1000);
    fprintf(fid, 'Demand Charge                0\n\n');

    % ----- [EMITTERS] -----
    fprintf(fid, '[EMITTERS]\n;Junction      Coefficient (LPM/sqrt(m))\n');
    fprintf(fid, ';-- TECHO %s --\n', asp_techo.Modelo{1});
    for i = 1:optima.n_techo
        fprintf(fid, 'JT%-2d           %.4f\n', i, Ke_techo);
    end
    fprintf(fid, ';-- PERIMETRO %s --\n', asp_perim.Modelo{1});
    for i = 1:optima.n_perim
        fprintf(fid, 'JP%-2d           %.4f\n', i, Ke_perim);
    end
    if usar_vent
        fprintf(fid, ';-- VENTANAS %s --\n', asp_vent.Modelo{1});
        for i = 1:n_vent_eff
            fprintf(fid, 'JV%-2d           %.4f\n', i, Ke_vent);
        end
    end
    fprintf(fid, '\n');

    fprintf(fid, '[QUALITY]\n\n[SOURCES]\n\n');
    fprintf(fid, '[REACTIONS]\nOrder Bulk                  1\nOrder Tank                  1\nOrder Wall                  1\n');
    fprintf(fid, 'Global Bulk                 0\nGlobal Wall                 0\nLimiting Potential          0\nRoughness Correlation       0\n\n');
    fprintf(fid, '[MIXING]\n\n');

    % ----- [TIMES] -----
    fprintf(fid, '[TIMES]\n');
    fprintf(fid, 'Duration                    %d:00\n', round(parametros.t_operacion_min/60));
    fprintf(fid, 'Hydraulic Timestep          0:05\nQuality Timestep            0:05\n');
    fprintf(fid, 'Pattern Timestep            1:00\nPattern Start               0:00\n');
    fprintf(fid, 'Report Timestep             0:05\nReport Start                0:00\n');
    fprintf(fid, 'Start ClockTime             12 am\nStatistic                   None\n\n');

    fprintf(fid, '[REPORT]\nStatus                      Yes\nSummary                     Yes\nPage                        0\nEnergy                      Yes\nNodes                       All\nLinks                       All\n\n');

    % ----- [OPTIONS] -----
    fprintf(fid, '[OPTIONS]\n');
    fprintf(fid, 'Units                       LPM\nHeadloss                    H-W\n');
    fprintf(fid, 'Specific Gravity            1.0\nViscosity                   1.0\n');
    fprintf(fid, 'Trials                      100\nAccuracy                    0.001\n');
    fprintf(fid, 'CHECKFREQ                   2\nMAXCHECK                    10\nDAMPLIMIT                   0\n');
    fprintf(fid, 'Unbalanced                  Continue 10\nPattern                     1\nDemand Multiplier           1.0\n');
    fprintf(fid, 'Emitter Exponent            0.5\nQuality                     None mg/L\n');
    fprintf(fid, 'Diffusivity                 1.0\nTolerance                   0.01\n\n');

    % ----- [COORDINATES] -----
    fprintf(fid, '[COORDINATES]\n;Node            X-Coord       Y-Coord\n');
    fprintf(fid, 'R_ESTANQUE       %.2f          %.2f\n', coords.R_ESTANQUE);
    fprintf(fid, 'J_MAN_S          %.2f          %.2f\n', coords.J_MAN_S);
    for i = 1:N
        fprintf(fid, 'J_B%d_S           %.2f          %.2f\n', i, xy_BS(i,1), xy_BS(i,2));
        fprintf(fid, 'J_B%d_D           %.2f          %.2f\n', i, xy_BD(i,1), xy_BD(i,2));
    end
    fprintf(fid, 'J_MAN_D          %.2f          %.2f\n', coords.J_MAN_D);
    for k = 1:m_est
        fprintf(fid, 'JA%-3d            %.2f         %.2f\n', k, est.xy(k,1), est.xy(k,2));
    end
    for i = 1:optima.n_techo
        fprintf(fid, 'JT%-2d             %.2f         %.2f\n', i, pos_techo(i,1), pos_techo(i,2));
    end
    for i = 1:optima.n_perim
        fprintf(fid, 'JP%-2d             %.2f         %.2f\n', i, pos_perim(i,1), pos_perim(i,2));
    end
    for i = 1:n_vent_eff
        fprintf(fid, 'JV%-2d             %.2f         %.2f\n', i, pos_vent(i,1), pos_vent(i,2));
    end
    fprintf(fid, '\n');

    fprintf(fid, '[VERTICES]\n\n');

    % ----- [LABELS] -----
    fprintf(fid, '[LABELS]\n');
    fprintf(fid, '%.2f  %.2f  "Anillo perimetral"\n', ...
            mean(contorno(1:end-1,1)), max(contorno(:,2)) + 0.6);
    fprintf(fid, '%.2f  %.2f  "Franja defensa perimetral"\n', bb(1)+0.3, bb(4)-0.3);
    fprintf(fid, '%.2f  %.2f  "Grupo bombeo"\n', coords.J_MAN_S(1), coords.J_MAN_S(2) + 0.8);
    fprintf(fid, '%.2f  %.2f  "Estanque"\n\n', coords.R_ESTANQUE(1), coords.R_ESTANQUE(2) - 0.5);

    % ----- [BACKDROP] -----
    fprintf(fid, '[BACKDROP]\n');
    fprintf(fid, 'DIMENSIONS      %.1f    %.1f    %.1f    %.1f\n', ...
            bb_all(1) - 1.0, bb_all(2) - 1.0, bb_all(3) + 1.0, bb_all(4) + 1.0);
    fprintf(fid, 'UNITS           Meters\n');
    fprintf(fid, 'OFFSET          0.0     0.0\n\n');

    fprintf(fid, '[END]\n');
    fclose(fid);
end


% =====================================================================
%  Auxiliares locales
% =====================================================================
function [p, nrm, s] = proyectar_contorno(contorno, q)
%PROYECTAR_CONTORNO  Punto mas cercano a q sobre el poligono cerrado, su
%   normal unitaria exterior y su abscisa curvilinea s (distancia recorrida
%   sobre el contorno desde el primer vertice). Mismo criterio que los
%   helpers de graficar_red_hidraulica.m.
    c = mean(contorno(1:end-1,:), 1);
    mejor = inf;  p = q;  nrm = [1 0];  s = 0;  s_acum = 0;
    for i = 1:size(contorno,1)-1
        a  = contorno(i,:);
        b  = contorno(i+1,:);
        ab = b - a;
        Lab = norm(ab);
        t  = max(0, min(1, dot(q-a, ab) / max(Lab^2, 1e-9)));
        pr = a + t*ab;
        d  = norm(q - pr);
        if d < mejor
            mejor = d;
            p = pr;
            s = s_acum + t*Lab;
            n1 = [ab(2), -ab(1)] / max(Lab, 1e-9);
            if dot(n1, pr - c) < 0, n1 = -n1; end
            nrm = n1;
        end
        s_acum = s_acum + Lab;
    end
end


function [est, iT, iP] = construir_estaciones(contorno, p_feed, st_techo, st_perim)
%CONSTRUIR_ESTACIONES  Nodos del anillo ordenados por abscisa curvilinea.
%   Fusiona las estaciones coincidentes (si n_techo == n_perim el montante
%   y el ramal comparten la TEE) y rota la numeracion para que la estacion
%   1 sea la alimentacion de la aduccion.
%       est.xy(k,:) : coordenadas del nodo JAk
%       est.s(k)    : abscisa curvilinea del nodo JAk [m]
%       est.L_total : perimetro del contorno [m]
%       iT(i), iP(j): estacion a la que se conecta cada montante / ramal.
    pts = [p_feed; st_techo; st_perim];
    n = size(pts, 1);
    s = zeros(n, 1);
    for i = 1:n
        [~, ~, s(i)] = proyectar_contorno(contorno, pts(i,:));
    end
    d = diff(contorno);
    L_total = sum(sqrt(sum(d.^2, 2)));

    % Agrupar puntos con la misma abscisa (tolerancia en metros)
    tol = 0.05;
    [s_ord, orden] = sort(s);
    grupo = zeros(n, 1);
    ng = 0;  s_grp = zeros(n, 1);
    for k = 1:n
        if ng == 0 || (s_ord(k) - s_grp(ng)) > tol
            ng = ng + 1;
            s_grp(ng) = s_ord(k);
        end
        grupo(orden(k)) = ng;
    end
    s_grp = s_grp(1:ng);
    % El lazo se cierra: el ultimo grupo puede coincidir con el primero
    if ng > 1 && (L_total - s_grp(ng) + s_grp(1)) <= tol
        grupo(grupo == ng) = 1;
        s_grp(ng) = [];
        ng = ng - 1;
    end

    % Rotar la numeracion para que el grupo de la alimentacion sea el 1
    g0 = grupo(1);
    nuevo = mod((0:ng-1)' - (g0-1), ng) + 1;   % nuevo(g) = indice rotado del grupo g
    grupo = reshape(nuevo(grupo), [], 1);
    s_rot = zeros(ng, 1);
    s_rot(nuevo) = s_grp;
    xy = zeros(ng, 2);
    for i = n:-1:1
        xy(grupo(i),:) = pts(i,:);   % coincidentes: cualquiera sirve (dif <= tol)
    end
    xy(grupo(1),:) = pts(1,:);       % la alimentacion fija su estacion

    est.xy = xy;
    est.s = s_rot;
    est.L_total = L_total;
    nT = size(st_techo, 1);
    iT = grupo(1 + (1:nT));
    iP = grupo(1 + nT + (1:size(st_perim,1)));
end
