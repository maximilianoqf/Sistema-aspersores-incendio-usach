function cache = bombas_construir_cache(pumps, N_max, HP_max, costo_acc)
%BOMBAS_CONSTRUIR_CACHE  Precalcula las combinaciones de bombas (con repetición)
%   para seleccionar_grupo_bombas. Se llama UNA vez por corrida; el resultado
%   no depende de la configuración hidráulica, solo del catálogo y los topes.
%
%   pumps     : struct con arreglos por modelo (ver seleccionar_grupo_bombas).
%   N_max     : nº máximo de unidades por grupo (parametros.n_bombas_paralelo_max).
%   HP_max    : tope de HP por unidad en grupos de más de una bomba.
%   costo_acc : vector de costos de accesorios indexado por nº de unidades.
%
%   cache.Cm        : matriz (n_combos × nb) de conteos por modelo.
%   cache.units     : nº de unidades de cada combinación.
%   cache.PHP_tot   : potencia de placa total por combinación [HP].
%   cache.PkW_tot   : potencia de placa total por combinación [kW].
%   cache.cap_ok    : combinaciones que respetan el tope de HP por unidad.
%   cache.cost_combo: costo de equipos (bombas + accesorios) por combinación.

    nb = numel(pumps.PHP);
    Cm = [];
    for k = 1:N_max
        Cm = [Cm; multisets_a_conteos(nb, k)]; %#ok<AGROW>
    end
    units = sum(Cm, 2);

    cache.Cm      = Cm;
    cache.units   = units;
    cache.PHP_tot = Cm * pumps.PHP;
    cache.PkW_tot = Cm * pumps.PkW;
    precio_fijo   = Cm * pumps.precio;

    % Tope de HP por unidad: aplica solo a grupos de más de una unidad
    bad     = pumps.PHP > HP_max;          % modelos que exceden el tope
    usa_bad = any(Cm(:, bad) > 0, 2);
    cache.cap_ok = (units == 1) | ~usa_bad;

    % Costo de accesorios según nº de unidades (último valor como tope)
    n_acc = numel(costo_acc);
    idx   = min(units, n_acc);
    cache.cost_combo = precio_fijo + costo_acc(idx)';
end


function Cm = multisets_a_conteos(nb, k)
    % Combinaciones con repetición de k unidades sobre nb modelos -> conteos.
    base = nchoosek(1:(nb + k - 1), k);     % subconjuntos
    M    = base - (0:k-1);                  % biyección a multiconjuntos (1..nb)
    Cm   = zeros(size(M,1), nb);
    for r = 1:size(M,1)
        for c = 1:k
            Cm(r, M(r,c)) = Cm(r, M(r,c)) + 1;
        end
    end
end
