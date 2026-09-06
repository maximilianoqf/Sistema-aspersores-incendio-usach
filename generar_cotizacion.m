function ruta_archivo = generar_cotizacion(optima, parametros, BD, ruta_archivo)
%GENERAR_COTIZACION  Genera un Excel simple con la cotización de materiales de
%   la configuración óptima, en cinco columnas:
%
%       Material | Cantidad | P. unitario [CLP] | Total [CLP] | Descripción
%
%   Incluye bomba(s), aspersores, nebulizador, tuberías e insumos de
%   instalación (lija, teflón, pegamento Vinilit), y una fila de Total.
%
%   ruta = generar_cotizacion(optima, parametros, BD, ruta_archivo)
%
%   'optima' es una fila de resultados.viables. Los precios de bomba/
%   aspersores/tuberías salen de las BD; las cantidades y precios de los
%   insumos son una estimación referencial (editable en el Excel o vía
%   parametros.consumibles = {desc, unidad, cantidad, precio; ...}).

    if nargin < 4 || isempty(ruta_archivo)
        ruta_archivo = 'cotizacion_optima.xlsx';
    end

    % =========================================================
    %  1. Datos de la configuración óptima desde las BD
    % =========================================================
    at = BD.aspersores(strcmp(BD.aspersores.Modelo, optima.asp_techo{1}), :);
    ap = BD.aspersores(strcmp(BD.aspersores.Modelo, optima.asp_perim{1}), :);

    usar_vent = optima.n_vent > 0;   % nebulizadores opcionales
    if usar_vent
        av = BD.aspersores(strcmp(BD.aspersores.Modelo, optima.asp_vent{1}), :);
    end

    tp = BD.tuberias(BD.tuberias.DN_mm == optima.DN_princ_mm & ...
                     strcmp(BD.tuberias.Material, optima.material_princ{1}), :);
    tr = BD.tuberias(BD.tuberias.DN_mm == optima.DN_ramal_mm & ...
                     strcmp(BD.tuberias.Material, optima.material_ramal{1}), :);

    % Longitudes del trazado real: aducción + anillo COMPLETO (principal),
    % un montante/ramal por aspersor (ramales) + mangueras del kit ventanas.
    L_adu    = obtener(parametros, 'L_aduccion_m', obtener(parametros, 'L_principal_m', 5));
    L_anillo = obtener(parametros, 'perimetro_m', 27.2);
    L_mont   = obtener(parametros, 'L_montante_techo_m', 2.1);
    L_rper   = obtener(parametros, 'L_ramal_perim_unit_m', 2.5);
    if usar_vent
        L_rv = obtener(parametros, 'L_ramal_vent_m', 0);
    else
        L_rv = 0;
    end
    Lp      = L_adu + L_anillo;
    L_ramal = optima.n_techo*L_mont + optima.n_perim*L_rper + L_rv;

    % Bombas por unidad física (grupo posiblemente mixto: "A;A;B")
    if ismember('bomba_lista', optima.Properties.VariableNames) && ~isempty(optima.bomba_lista{1})
        modelos_unidad = strsplit(optima.bomba_lista{1}, ';');
    else
        modelos_unidad = repmat(optima.bomba_modelo(1), 1, optima.n_bombas);
    end
    [mods_unicos, ~, ix] = unique(modelos_unidad, 'stable');
    conteo_bomba = accumarray(ix(:), 1);

    % =========================================================
    %  2. Filas de la cotización
    % =========================================================
    filas = {};   % cada fila: {Material, "cant unidad", P.unitario, Total, Descripción}

    % --- Bomba(s) ---
    for k = 1:numel(mods_unicos)
        b = BD.bombas(strcmp(BD.bombas.Modelo, mods_unicos{k}), :);
        filas = fila(filas, sprintf('Electrobomba %s', b.Modelo{1}), conteo_bomba(k), 'u', ...
            b.Precio_CLP, sprintf('%s · %.1f HP', b.Marca{1}, b.P_HP));
    end
    if optima.n_bombas > 1
        acc = parametros.costo_accesorios_paralelo;
        costo_acc = acc(min(optima.n_bombas, numel(acc)));
        filas = fila(filas, 'Accesorios para paralelo', 1, 'gl', costo_acc, ...
            'Manifold, válvulas check y controlador alternante');
    end

    % --- Aspersores y nebulizador ---
    filas = fila(filas, sprintf('Aspersor %s', at.Modelo{1}), optima.n_techo, 'u', ...
        at.Precio_CLP, sprintf('Techo · K=%.2f', at.K_factor));
    filas = fila(filas, sprintf('Aspersor %s', ap.Modelo{1}), optima.n_perim, 'u', ...
        ap.Precio_CLP, sprintf('Perímetro · K=%.2f', ap.K_factor));
    if usar_vent
        filas = fila(filas, sprintf('Nebulizador %s', av.Modelo{1}), optima.n_vent, 'u', ...
            av.Precio_CLP, sprintf('Ventanas · K=%.2f', av.K_factor));
    end

    % --- Tuberías ---
    filas = fila(filas, sprintf('Tubería %s DN%d', optima.material_princ{1}, optima.DN_princ_mm), ...
        Lp, 'm', tp.Precio_CLP_m, 'Aducción + anillo perimetral');
    filas = fila(filas, sprintf('Tubería %s DN%d', optima.material_ramal{1}, optima.DN_ramal_mm), ...
        L_ramal, 'm', tr.Precio_CLP_m, 'Montantes techo + ramales perímetro (+kit ventanas)');

    % --- Insumos de instalación ---
    consum = consumibles_default(parametros, optima, Lp + L_ramal);
    for k = 1:size(consum,1)
        filas = fila(filas, consum{k,1}, consum{k,3}, consum{k,2}, consum{k,4}, ...
            'Insumo de instalación (referencial)');
    end

    % =========================================================
    %  3. Armar la planilla y el total
    % =========================================================
    total = 0;
    for r = 1:size(filas,1), total = total + filas{r,4}; end

    C = {};
    C(end+1,:) = {'COTIZACIÓN DE MATERIALES — Sistema contra incendios (config. óptima)', '', '', '', ''};
    C(end+1,:) = {sprintf('%s · Vivienda %s %.1f×%.1f m · Q %.0f L/min · HMT %.1f m', ...
        datestr(now,'yyyy-mm-dd'), upper(parametros.disp.forma), parametros.disp.largo_m, ...
        parametros.disp.ancho_m, optima.Q_diseno_Lmin, optima.HMT_m), '', '', '', ''};
    C(end+1,:) = {'', '', '', '', ''};
    C(end+1,:) = {'Material', 'Cantidad', 'P. unitario [CLP]', 'Total [CLP]', 'Descripción'};
    for r = 1:size(filas,1)
        C(end+1,:) = {filas{r,1}, filas{r,2}, round(filas{r,3}), round(filas{r,4}), filas{r,5}}; %#ok<AGROW>
    end
    C(end+1,:) = {'', '', '', '', ''};
    C(end+1,:) = {'Total', '', '', round(total), ''};

    % =========================================================
    %  4. Escribir a Excel y dar formato (bordes + encabezado pastel)
    % =========================================================
    if exist(ruta_archivo, 'file'), delete(ruta_archivo); end
    writecell(C, ruta_archivo, 'Sheet', 'Cotización');

    n_filas = size(filas, 1);
    r_hdr = 4;  r_fin = 4 + n_filas;  r_tot = 6 + n_filas;   % filas clave de la planilla
    try
        info = dir(ruta_archivo);
        aplicar_formato(fullfile(info.folder, info.name), r_hdr, r_fin, r_tot);
    catch ME
        warning('generar_cotizacion:formato', ...
            ['No se pudo aplicar el formato (bordes/colores): %s\n' ...
             'El archivo se generó igualmente, pero sin formato.'], ME.message);
    end
end


% =====================================================================
%  FORMATO DE LA PLANILLA (vía automatización de Excel / COM en Windows)
% =====================================================================
function aplicar_formato(ruta_abs, r_hdr, r_fin, r_tot)
    xlContinuous = 1;  xlThin = 2;  xlThick = 4;  negro = 0;
    pastel = 197 + 217*256 + 241*65536;        % azul pastel (RGB 197,217,241)

    Excel = actxserver('Excel.Application');
    limpiar = onCleanup(@() cerrar_excel(Excel));   % garantiza cerrar Excel
    Excel.Visible = false;  Excel.DisplayAlerts = false;
    wb = Excel.Workbooks.Open(ruta_abs);
    ws = wb.Worksheets.Item('Cotización');

    % Grilla (encabezado + ítems): borde exterior grueso, interior fino
    grilla = ws.Range(sprintf('A%d:E%d', r_hdr, r_fin));
    set_bordes(grilla, [7 8 9 10], xlContinuous, xlThick, negro);   % bordes exteriores
    set_bordes(grilla, [11 12],    xlContinuous, xlThin,  negro);   % líneas interiores

    % Encabezado: relleno pastel + negrita
    hdr = ws.Range(sprintf('A%d:E%d', r_hdr, r_hdr));
    hdr.Interior.Color = pastel;
    hdr.Font.Bold = true;

    % Fila Total: caja gruesa + negrita
    tot = ws.Range(sprintf('A%d:E%d', r_tot, r_tot));
    set_bordes(tot, [7 8 9 10], xlContinuous, xlThick, negro);
    tot.Font.Bold = true;

    % Título en negrita y autoajuste de columnas
    ws.Range('A1').Font.Bold = true;
    ws.UsedRange.Columns.AutoFit;

    wb.Save;  wb.Close(false);
end

function set_bordes(rng, indices, estilo, peso, color)
    for b = indices
        bo = rng.Borders.Item(b);
        bo.LineStyle = estilo;  bo.Weight = peso;  bo.Color = color;
    end
end

function cerrar_excel(Excel)
    try
        Excel.Quit;
    catch
    end
    try
        delete(Excel);
    catch
    end
end


% =====================================================================
%  HELPERS
% =====================================================================
function filas = fila(filas, material, cant, unidad, precio_unit, descr)
    % Agrega {Material, Cantidad (con unidad), P. unitario, Total, Descripción}.
    filas(end+1,:) = {material, sprintf('%g %s', cant, unidad), precio_unit, cant*precio_unit, descr};
end

function consum = consumibles_default(parametros, optima, L_tub_total)
    % Override opcional: parametros.consumibles = {desc, unidad, cant, precio; ...}
    if isfield(parametros, 'consumibles') && ~isempty(parametros.consumibles)
        consum = parametros.consumibles;
        return;
    end
    n_asp = optima.n_techo + optima.n_perim + optima.n_vent;
    % Rindes referenciales: teflón ~1 rollo/15 uniones, pegamento ~1 tarro/30 m,
    % lija ~1 pliego/20 m de tubería.
    teflon_rollos    = max(1, ceil(n_asp / 15));
    pegamento_tarros = max(1, ceil(L_tub_total / 30));
    lija_pliegos     = max(1, ceil(L_tub_total / 20));
    consum = {
        'Lija al agua',      'pliego', lija_pliegos,      800;
        'Teflón',            'rollo',  teflon_rollos,     600;
        'Pegamento Vinilit', 'tarro',  pegamento_tarros, 6500;
    };
end
