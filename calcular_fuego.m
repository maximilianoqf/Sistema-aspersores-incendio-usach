function res = calcular_fuego(caso)
%CALCULAR_FUEGO  Deriva, a partir de un caso de vegetación/ambiente, los
%   parámetros que el optimizador hidráulico necesitaba "a mano":
%       densidad_techo_Lmin_m2, densidad_perimetro_Lmin_m2, t_operacion_min
%
%   Cadena: Rothermel 1972/Albini 1976 -> Byram -> flujo radiante (factor de
%   vista) -> atenuación de cortina (Beer-Lambert) -> balance de energía.
%
%   caso: struct con campos
%       .nombre, .w0_kgm2, .sav_1m, .delta_m, .Mf, .Mx, .viento_ms
%       .pendiente_tan (opc, def 0), .d_pared_m (opc, def 5), .tipo (opc, 'superficie'|'copa')
%
%   OJO: varias constantes en constantes_fuego() son PROVISORIAS (@CITA);
%   son las que debes respaldar con literatura en la tesis.

    FUEGO = constantes_fuego();

    % --- Valores por defecto (equivalentes a los || de JS) ---
    if ~isfield(caso,'nombre')        || isempty(caso.nombre),        caso.nombre = '';            end
    if ~isfield(caso,'pendiente_tan') || isempty(caso.pendiente_tan), caso.pendiente_tan = 0;      end
    if ~isfield(caso,'d_pared_m')     || isempty(caso.d_pared_m),     caso.d_pared_m = 5;          end
    if ~isfield(caso,'tipo')          || isempty(caso.tipo),          caso.tipo = 'superficie';    end

    combustible = struct('w0_kgm2',caso.w0_kgm2, 'sav_1m',caso.sav_1m, ...
                         'delta_m',caso.delta_m, 'Mf',caso.Mf, 'Mx',caso.Mx);
    ambiente    = struct('viento_ms',caso.viento_ms, 'pendiente_tan',caso.pendiente_tan);

    r = rothermel(combustible, ambiente);

    d    = caso.d_pared_m;       % anillo despejado [m]
    tipo = caso.tipo;

    R_ms    = r.R_ms;
    I_Byram = r.I_Byram_kWm;
    L_llama = r.L_llama_m;
    nota    = '';

    if strcmpi(tipo, 'copa')
        % Rothermel (superficie) NO es válido en fuego de copa: se acota R a
        % un máximo plausible y se usa el poder emisivo de fuego de copa.
        if R_ms > FUEGO.ROS_extremo_max_ms
            R_ms = FUEGO.ROS_extremo_max_ms;
            nota = 'ROS acotado al máximo plausible (Rothermel no válido en fuego de copa)';
        end
        E_llama = FUEGO.E_llama_copa_kWm2;
        I_Byram = FUEGO.h_kJkg * caso.w0_kgm2 * R_ms;
        L_llama = 0.0775 * I_Byram^0.46;
    else
        E_llama = FUEGO.E_llama_superficie_kWm2;
    end

    % Techo: expuesto a radiación + pavesas, SIN cortina interpuesta
    flujo_techo = flujo_radiante(L_llama, d, E_llama, false);
    dens_techo  = densidad_requerida(flujo_techo.q_neto_kWm2);

    % Perímetro: cortina de agua interpuesta (atenuación Beer-Lambert)
    flujo_perim = flujo_radiante(L_llama, d, E_llama, true);
    dens_perim  = densidad_requerida(flujo_perim.q_neto_kWm2);

    % Tiempo de operación: prehumectación + paso del frente + pavesas
    if R_ms > 0
        t_frente_min = (FUEGO.prof_frente_m / R_ms) / 60;
    else
        t_frente_min = 0;
    end
    t_op = FUEGO.t_prehumect_min + t_frente_min + FUEGO.t_pavesas_min;

    % --- Empaquetar resultados ---
    res.nombre   = caso.nombre;
    res.tipo     = tipo;
    res.nota     = nota;
    % diagnóstico de fuego
    res.R_ms     = R_ms;
    res.R_mmin   = R_ms * 60;
    res.IR_kWm2  = r.IR_kWm2;
    res.I_Byram_kWm = I_Byram;
    res.L_llama_m   = L_llama;
    res.q_inc_techo_kWm2  = flujo_techo.q_inc_kWm2;
    res.q_neto_techo_kWm2 = flujo_techo.q_neto_kWm2;
    res.q_neto_perim_kWm2 = flujo_perim.q_neto_kWm2;
    res.ignicion_sin_proteccion = flujo_techo.q_inc_kWm2 > FUEGO.q_crit_kWm2;
    % salidas que consume el optimizador
    res.densidad_techo_Lmin_m2     = max(dens_techo, 0);
    res.densidad_perimetro_Lmin_m2 = max(dens_perim, 0);
    res.t_operacion_min = t_op;
    res.t_frente_min    = t_frente_min;
end


% =====================================================================
%  CONSTANTES FÍSICAS / EMPÍRICAS  (marcar @CITA al referenciarlas)
% =====================================================================
function FUEGO = constantes_fuego()
    % Combustible
    FUEGO.h_kJkg     = 18000;    % poder calorífico @CITA (~18 MJ/kg vegetación)
    FUEGO.ST         = 0.0555;   % contenido mineral total (Rothermel)
    FUEGO.SE         = 0.010;    % contenido mineral efectivo (Rothermel)
    % Exposición / radiación
    FUEGO.E_llama_superficie_kWm2 = 100;  % poder emisivo llama superficie [kW/m2] @CITA Butler2004
    FUEGO.E_llama_copa_kWm2       = 200;  % poder emisivo fuego de copa [kW/m2] @CITA Butler2004
    FUEGO.q_crit_kWm2   = 12.5;  % flujo crítico ignición piloteada @CITA McAllister2010
    FUEGO.ancho_frente_m = 10;   % ancho del frente "visto" por la pared @CITA
    FUEGO.ROS_extremo_max_ms = 0.5;  % tope plausible de ROS (caso copa) @CITA
    % Cortina de agua (Beer-Lambert)
    FUEGO.kappa_1m    = 1.0;     % coef. de extinción de la cortina [1/m] @CITA
    FUEGO.L_cortina_m = 0.3;     % espesor efectivo de la cortina [m] @CITA
    % Agua
    FUEGO.h_fg_kJkg    = 2257;   % calor latente de vaporización a 100°C
    FUEGO.c_agua_kJkgK = 4.186;  % calor específico del agua
    FUEGO.dT_agua_K    = 80;     % calentamiento del agua antes de evaporar
    FUEGO.eta_aplicacion = 0.5;  % eficiencia de aplicación (escurrimiento+deriva) @CITA
    % Tiempos de operación [min]
    FUEGO.t_prehumect_min = 15;  % prehumectación antes del frente @CITA
    FUEGO.t_pavesas_min   = 45;  % fase de pavesas residuales @CITA
    FUEGO.prof_frente_m   = 2;   % profundidad de la zona de llama Δ [m] @CITA
end


function CONV = conversiones()
    CONV.load_kgm2_to_lbft2   = 0.204816;
    CONV.sav_1m_to_1ft        = 0.3048;
    CONV.m_to_ft              = 1 / 0.3048;
    CONV.ms_to_ftmin          = 196.850;
    CONV.Rftmin_to_ms         = 0.3048 / 60;
    CONV.kJkg_to_BTUlb        = 1 / 2.326;
    CONV.IR_BTUft2min_to_kWm2 = 0.18927;
end


% =====================================================================
%  MODELO DE ROTHERMEL (combustible muerto, una clase de tamaño)
% =====================================================================
function r = rothermel(combustible, ambiente)
    FUEGO = constantes_fuego();
    CONV  = conversiones();

    % --- a unidades inglesas ---
    w0    = combustible.w0_kgm2 * CONV.load_kgm2_to_lbft2;   % lb/ft2
    sigma = combustible.sav_1m  * CONV.sav_1m_to_1ft;        % 1/ft
    delta = combustible.delta_m * CONV.m_to_ft;             % ft
    Mf = combustible.Mf;  Mx = combustible.Mx;
    U = ambiente.viento_ms * CONV.ms_to_ftmin;              % ft/min
    tan_phi = ambiente.pendiente_tan;
    h = FUEGO.h_kJkg * CONV.kJkg_to_BTUlb;                  % BTU/lb

    % --- empaquetamiento ---
    rho_b = w0 / delta;                                     % lb/ft3
    rho_p = 32;                                             % lb/ft3
    beta = rho_b / rho_p;
    beta_op = 3.348 * sigma^(-0.8189);
    ratio = beta / beta_op;

    % --- velocidad de reacción ---
    Gamma_max = sigma^1.5 / (495 + 0.0594 * sigma^1.5);
    A = 133 * sigma^(-0.7913);
    Gamma = Gamma_max * ratio^A * exp(A * (1 - ratio));

    % --- amortiguamientos ---
    wn = w0 / (1 + FUEGO.ST);                               % carga neta
    rm = min(Mf / Mx, 1);
    etaM = max(0, 1 - 2.59*rm + 5.11*rm^2 - 3.52*rm^3);
    etaS = min(1, 0.174 * FUEGO.SE^(-0.19));

    % --- intensidad de reacción ---
    IR = Gamma * wn * h * etaM * etaS;                      % BTU/ft2/min

    % --- razón de flujo propagante ---
    xi = exp((0.792 + 0.681*sqrt(sigma)) * (beta + 0.1)) / (192 + 0.2595*sigma);

    % --- factores de viento y pendiente ---
    C = 7.47 * exp(-0.133 * sigma^0.55);
    B = 0.02526 * sigma^0.54;
    E = 0.715 * exp(-3.59e-4 * sigma);
    U_lim = 0.9 * IR;                 % límite de viento de Rothermel @CITA
    U_ef  = min(U, U_lim);
    if U_ef > 0
        phi_w = C * U_ef^B * ratio^(-E);
    else
        phi_w = 0;
    end
    phi_s = 5.275 * beta^(-0.3) * max(tan_phi, 0)^2;

    % --- preignición ---
    Qig    = 250 + 1116 * Mf;         % BTU/lb
    eps_ig = exp(-138 / sigma);       % nº efectivo de calentamiento

    % --- velocidad de propagación ---
    R_ftmin = IR * xi * (1 + phi_w + phi_s) / (rho_b * eps_ig * Qig);
    R_ms    = R_ftmin * CONV.Rftmin_to_ms;
    IR_kWm2 = IR * CONV.IR_BTUft2min_to_kWm2;

    % --- Byram: intensidad de línea y longitud de llama ---
    I_Byram = FUEGO.h_kJkg * combustible.w0_kgm2 * R_ms;    % kW/m
    L_llama = 0.0775 * I_Byram^0.46;                        % m

    r.R_ms = R_ms;  r.IR_kWm2 = IR_kWm2;
    r.I_Byram_kWm = I_Byram;  r.L_llama_m = L_llama;
end


% =====================================================================
%  FACTOR DE VISTA pared vertical <-> frente de llama rectangular
% =====================================================================
function F = factor_vista(L_llama_m, ancho_m, d_m)
    a = (ancho_m / 2) / d_m;       % semiancho / distancia
    b = (L_llama_m / 2) / d_m;     % semialto / distancia
    Fcuad = (1 / (2*pi)) * ( ...
        (a / sqrt(1 + a^2)) * atan(b / sqrt(1 + a^2)) + ...
        (b / sqrt(1 + b^2)) * atan(a / sqrt(1 + b^2)) );
    F = 4 * Fcuad;                 % elemento opuesto al centro = 4 cuadrantes
end


% =====================================================================
%  FLUJO RADIANTE incidente sobre la pared (con/sin cortina)
% =====================================================================
function flujo = flujo_radiante(L_llama_m, d_m, E_llama_kWm2, con_cortina)
    FUEGO = constantes_fuego();
    F = factor_vista(L_llama_m, FUEGO.ancho_frente_m, d_m);
    q_inc = E_llama_kWm2 * F;
    if con_cortina
        atenua = exp(-FUEGO.kappa_1m * FUEGO.L_cortina_m);
    else
        atenua = 1;
    end
    flujo.q_inc_kWm2  = q_inc;
    flujo.q_neto_kWm2 = q_inc * atenua;
end


% =====================================================================
%  DENSIDAD DE AGUA requerida para abatir el exceso sobre q_crit
% =====================================================================
function dens_Lminm2 = densidad_requerida(q_neto_kWm2)
    FUEGO = constantes_fuego();
    exceso = max(0, q_neto_kWm2 - FUEGO.q_crit_kWm2);   % kW/m2 a remover
    energia_kJkg = (FUEGO.c_agua_kJkgK * FUEGO.dT_agua_K + FUEGO.h_fg_kJkg) * FUEGO.eta_aplicacion;
    masica_kgsm2 = exceso / energia_kJkg;               % kg/s/m2
    dens_Lminm2 = masica_kgsm2 * 60;                    % L/min/m2
end