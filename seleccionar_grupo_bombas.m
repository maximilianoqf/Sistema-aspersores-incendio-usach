function sel = seleccionar_grupo_bombas(pumps, cache, Q_princ, HMT, H_est, H_asp, fa, rho, g)
%SELECCIONAR_GRUPO_BOMBAS  Elige el grupo de bombeo más barato (1 unidad o
%   varias en paralelo, IGUALES O DE DISTINTO MODELO) que cubre (Q_princ, HMT)
%   y respeta el margen de potencia instalada (factor de arranque).
%
%   sel = seleccionar_grupo_bombas(pumps, cache, Q_princ, HMT, H_est, H_asp, fa, rho, g)
%
%   MODELO FÍSICO
%   -------------
%   Las bombas en paralelo SUMAN CAUDALES a una misma altura (head); no se
%   suman potencias. Una bomba aporta caudal a una altura H solo si H está
%   por debajo de su altura de cierre (shutoff). La factibilidad se evalúa
%   como  Q_total(HMT) = Σ nᵢ·qᵢ(HMT) ≥ Q_princ  (equivale, para curvas
%   monótonas, a que la curva combinada entregue al menos HMT a Q_princ).
%   La eficiencia del grupo es el promedio ponderado por caudal, que es
%   idéntico a sumar la potencia al eje de cada bomba:
%       η_grupo(H) = Σ nᵢ·qᵢ(H) / Σ nᵢ·qᵢ(H)/ηᵢ
%
%   ENTRADAS
%       pumps : struct con arreglos por modelo (columna nb×1 salvo celdas):
%               PHP, PkW, precio, eff_n (eficiencia normalizada 0–1),
%               Hmax, Qmax, modelo (cell), marca (cell),
%               Hs (cell, head ascendente), Qs (cell, caudal asociado).
%       cache : struct de seleccionar_grupo_bombas('cache', ...) con las
%               combinaciones precomputadas (ver build_cache).
%       Q_princ : caudal de diseño [L/min];  HMT : altura requerida [m].
%       H_est, H_asp : componentes de la curva del sistema (estática y aspersor).
%       fa  : factor de arranque (margen de potencia instalada).
%       rho, g : constantes (kg/m³, m/s²).
%
%   SALIDA sel (sel.ok=false si ninguna combinación sirve):
%       ok, n (unidades), PHP, PkW, costo, lista (cell de modelos por unidad),
%       modelo_str, marca_str, eficiencia (η_grupo en el punto de diseño, 0–1),
%       Q_oper, H_oper, P_kW_cons, HP_req.

    % La caché de combinaciones se construye una vez con bombas_construir_cache.
    Cm   = cache.Cm;
    nb   = size(Cm, 2);

    % Caudal que aporta cada modelo a la altura HMT
    qH = zeros(nb, 1);
    for i = 1:nb
        qH(i) = qflow(pumps.Hs{i}, pumps.Qs{i}, pumps.Hmax(i), pumps.Qmax(i), HMT);
    end

    Qcap  = Cm * qH;                       % caudal total del grupo a la altura HMT
    denom = Cm * (qH ./ pumps.eff_n);      % Σ nᵢ·qᵢ/ηᵢ
    Phidr = rho * g * (Q_princ/60000) * HMT;          % potencia hidráulica de diseño [W]
    shaftHP = Phidr * denom ./ max(Qcap, eps) / 745.7;  % potencia al eje del grupo [HP]

    valid = (Qcap >= Q_princ) & cache.cap_ok & (cache.PHP_tot >= fa .* shaftHP);
    if ~any(valid)
        sel.ok = false; return;
    end

    costos = cache.cost_combo;  costos(~valid) = inf;
    [~, best] = min(costos);
    counts = Cm(best, :);
    used   = find(counts > 0);

    eta_design = Qcap(best) / max(denom(best), eps);

    % --- Curva combinada del grupo para el punto de operación ---
    Hmax_b = max(pumps.Hmax(used));
    Hgrid  = linspace(0, Hmax_b, 300);
    Qtot   = zeros(size(Hgrid));
    for j = used
        Qtot = Qtot + counts(j) * qflow(pumps.Hs{j}, pumps.Qs{j}, ...
                                        pumps.Hmax(j), pumps.Qmax(j), Hgrid);
    end
    % Ordenar por caudal ascendente y dejar valores únicos para interp1
    [Qa, ord] = sort(Qtot);  Ha = Hgrid(ord);
    [Qu, iu]  = unique(Qa, 'last');  Hu = Ha(iu);

    [Q_oper, H_oper] = punto_operacion(Qu, Hu, Q_princ, HMT, H_est, H_asp);

    % --- Energía en el punto de operación (η del grupo a esa altura) ---
    qOp = zeros(1, numel(used));
    for k = 1:numel(used)
        j = used(k);
        qOp(k) = counts(j) * qflow(pumps.Hs{j}, pumps.Qs{j}, ...
                                   pumps.Hmax(j), pumps.Qmax(j), H_oper);
    end
    Qop_sum = sum(qOp);
    den_op  = sum(qOp ./ pumps.eff_n(used)');
    if den_op > 0 && Qop_sum > 0
        eta_op = Qop_sum / den_op;
        P_kW_cons = (rho*g*(Q_oper/60000)*H_oper / eta_op) / 1000;
    else
        P_kW_cons = cache.PkW_tot(best);     % sin eficiencia válida → placa
    end

    % --- Descriptores del grupo ---
    lista = {};
    partes = {};
    for j = used
        lista = [lista, repmat(pumps.modelo(j), 1, counts(j))]; %#ok<AGROW>
        partes{end+1} = sprintf('%d×%s', counts(j), pumps.modelo{j}); %#ok<AGROW>
    end
    if isscalar(used)
        marca_str = pumps.marca{used};
    else
        marca_str = 'Mixto';
    end

    sel.ok         = true;
    sel.n          = sum(counts);
    sel.PHP        = cache.PHP_tot(best);
    sel.PkW        = cache.PkW_tot(best);
    sel.costo      = cache.cost_combo(best);
    sel.lista      = lista;
    sel.modelo_str = strjoin(partes, ' + ');
    sel.marca_str  = marca_str;
    sel.eficiencia = eta_design;
    sel.Q_oper     = Q_oper;
    sel.H_oper     = H_oper;
    sel.P_kW_cons  = P_kW_cons;
    sel.HP_req     = Phidr / eta_design / 745.7;
end


% =====================================================================
%  UTILIDADES
% =====================================================================
function q = qflow(Hs, Qs, Hmax, Qmax, H)
    % Caudal que entrega una bomba a la altura H (0 sobre el shutoff,
    % caudal de runout bajo el rango de la curva).
    q = interp1(Hs, Qs, H, 'linear');
    q(H > Hmax)    = 0;
    q(H < Hs(1))   = Qmax;     % Hs está en orden ascendente
    q(isnan(q))    = 0;
end


function [Q_oper, H_oper] = punto_operacion(Qcurve, Hcurve, Q_princ, HMT, H_est, H_asp)
    % Intersección curva del grupo ↔ curva del sistema (aspersor∝Q², fricción∝Q^1.852).
    k_fric = (HMT - H_est - H_asp) / Q_princ^1.852;
    Q_lo = max(min(Qcurve), 1e-6);  Q_hi = max(Qcurve);
    Q_test = linspace(Q_lo, Q_hi, 400);
    H_b = interp1(Qcurve, Hcurve, Q_test, 'linear');
    H_s = H_est + H_asp.*(Q_test./Q_princ).^2 + k_fric.*Q_test.^1.852;
    d = H_b - H_s;
    ic = find(d(1:end-1).*d(2:end) < 0, 1);
    if ~isempty(ic)
        x1 = Q_test(ic);  x2 = Q_test(ic+1);
        y1 = d(ic);       y2 = d(ic+1);
        Q_oper = x1 - y1*(x2-x1)/(y2-y1);
        H_oper = interp1(Qcurve, Hcurve, Q_oper, 'linear');
    else
        Q_oper = Q_princ;  H_oper = HMT;
    end
end
