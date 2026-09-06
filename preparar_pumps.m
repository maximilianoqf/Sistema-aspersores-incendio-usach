function pumps = preparar_pumps(bombas)
%PREPARAR_PUMPS  Extrae el catálogo de bombas (table) a arreglos planos y
%   preprocesa las curvas para seleccionar_grupo_bombas / bombas_construir_cache.
%
%   pumps.PHP, .PkW, .precio          : columnas numéricas por modelo.
%   pumps.modelo, .marca              : celdas de texto por modelo.
%   pumps.eff_n                       : eficiencia normalizada a fracción 0–1.
%   pumps.Hs{i}, .Qs{i}               : curva con head ascendente y único (interp1).
%   pumps.Hmax(i), .Qmax(i)           : altura de cierre y caudal de runout.

    nb = height(bombas);
    pumps.PHP    = bombas.P_HP;
    pumps.PkW    = bombas.P_kW;
    pumps.precio = bombas.Precio_CLP;
    pumps.modelo = bombas.Modelo;
    pumps.marca  = bombas.Marca;
    pumps.eff_n  = arrayfun(@normalizar_eff, bombas.Eficiencia_global);
    pumps.Hs = cell(nb,1);  pumps.Qs = cell(nb,1);
    pumps.Hmax = zeros(nb,1);  pumps.Qmax = zeros(nb,1);
    for i = 1:nb
        Q = bombas.Q_curva{i}(:);  H = bombas.H_curva{i}(:);
        [Hu, iu] = unique(H);                 % head ascendente y único para interp1
        pumps.Hs{i} = Hu;  pumps.Qs{i} = Q(iu);
        pumps.Hmax(i) = max(H);  pumps.Qmax(i) = max(Q);
    end
end


function e = normalizar_eff(e)
    % Lleva la eficiencia a fracción 0–1 (admite % o dato inválido).
    if isempty(e) || isnan(e) || e <= 0, e = 1;
    elseif e > 1, e = e/100; end
end
