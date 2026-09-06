function gui_sistema_incendio()
%GUI_SISTEMA_INCENDIO  Interfaz grafica para el dimensionamiento del sistema
%   hidraulico contra incendios forestales.
%
%   PESTANAS:
%       1. Vivienda y sistema           (geometria + longitudes)
%       2. Modelo de fuego              (Rothermel/Byram -> densidades y t_operacion)
%       3. Criterios y restricciones    (densidades, modo, velocidades)
%       4. Iteracion y bombas           (rangos, diametros, paralelo)
%       5. Resultados                   (top-10, optima, KPIs, Pareto)
%       6. Editor BDs                   (tablas editables aspersores/tuberias/bombas)
%       7. Comparador                   (hasta 3 escenarios guardados)
%
%   BOTONES DEL FOOTER:
%       Ejecutar analisis           corre la iteracion
%       Graficos / Layout           abre las figuras detalladas
%       Exportar Excel              guarda resultados_viables.xlsx
%       Generar EPANET              escribe sistema_incendio.inp
%       Guardar config / Cargar     persiste parametros e iteracion (.mat)
%       Reset                       devuelve a defaults
%   (El boton "Guardar escenario" del comparador esta en la pestana 6.)

    % =====================================================================
    %  ESTADO COMPARTIDO
    % =====================================================================
    app = struct();
    app.parametros = parametros_default();
    app.iteracion  = iteracion_default();
    app.BD         = [];
    app.resultados = [];
    app.escenarios = {};            % cell array, cada elemento es un struct
    app.handles    = struct();

    % =====================================================================
    %  CREAR LA UIFIGURE
    % =====================================================================
    fig = uifigure('Name', 'Sistema Contra Incendios — Dimensionamiento', ...
                   'Position', [60 40 1500 880], 'Color', [0.96 0.96 0.97]);

    grid_main = uigridlayout(fig, [2 1]);
    grid_main.RowHeight  = {'1x', 110};
    grid_main.RowSpacing = 5;
    grid_main.Padding    = [10 10 10 5];

    % --- TabGroup ---
    tg = uitabgroup(grid_main);
    tg.Layout.Row = 1;
    app.handles.tg = tg;

    tab1     = uitab(tg, 'Title', '  1. Vivienda y sistema  ');
    tab_fueg = uitab(tg, 'Title', '  2. Modelo de fuego  ');
    tab2     = uitab(tg, 'Title', '  3. Criterios y restricciones  ');
    tab3     = uitab(tg, 'Title', '  4. Iteración y bombas  ');
    tab4     = uitab(tg, 'Title', '  5. Resultados  ');
    tab5     = uitab(tg, 'Title', '  6. Editor BDs  ');
    tab6     = uitab(tg, 'Title', '  7. Comparador  ');
    app.handles.tab_resultados = tab4;   % referencia robusta (sin índice fijo)

    crear_tab_vivienda(tab1);
    crear_tab_fuego(tab_fueg);
    crear_tab_criterios(tab2);
    crear_tab_iteracion(tab3);
    crear_tab_resultados(tab4);
    crear_tab_editor_bds(tab5);
    crear_tab_comparador(tab6);

    % --- Footer ---
    panel_footer = uipanel(grid_main, 'BorderType', 'line', ...
                           'BackgroundColor', [0.92 0.94 0.97]);
    panel_footer.Layout.Row = 2;
    crear_footer(panel_footer);

    % --- Carga inicial ---
    cargar_BDs();

    % =====================================================================
    %  ============  NESTED FUNCTIONS  ============
    % =====================================================================

    function p = parametros_default()
        % area_techo_m2, perimetro_m y area_perimetro_m2 NO se fijan aquí:
        % se derivan de la geometría paramétrica al final de esta función.
        p.ancho_franja_m     = 2.5;
        p.n_ventanas         = 5;
        p.usar_nebulizadores = true;    % incluir zona de ventanas en la evaluación

        % --- Trazado real: estanque → aducción → anillo perimetral cerrado ---
        % (la longitud del anillo = perímetro de la vivienda, derivado de la
        %  geometría; el camino crítico de fricción usa aducción + ½ anillo)
        p.L_aduccion_m         = 5.0;   % estanque/bomba → anillo
        p.anillo_cerrado       = true;  % el anillo alimenta por ambos lados
        p.L_montante_techo_m   = 2.1;   % montante vertical POR aspersor de techo
        p.L_ramal_perim_unit_m = 2.5;   % ramal horizontal POR aspersor de perímetro
        p.L_ramal_vent_m       = 14;    % mangueras kit nebulización (solo costo)

        % --- Cotas (alturas estáticas por zona) ---
        p.z_agua_estanque_m  = 0.0;     % espejo de agua del estanque (peor caso)
        p.z_aspersor_vent_m  = 1.5;     % altura de los nebulizadores de ventana

        % --- Conexión reducida al aspersor (1/2") y accesorios (K) ---
        p.conexion_D_int_mm  = 15.8;    % niple 1/2" (galvanizado; PVC DN20 ≈ 17)
        p.conexion_C_HW      = 140;
        p.conexion_L_m       = 0.3;
        p.K_tee              = 1.8;     % TEE derivación anillo→ramal
        p.K_codo             = 0.9;     % codo 90° del ramal perimetral
        p.K_buje             = 0.4;     % por buje reductor (con v del lado chico)
        p.n_bujes            = 2;

        p.densidad_techo_Lmin_m2     = 2.0;
        p.densidad_perimetro_Lmin_m2 = 1.0;
        p.modo_activacion    = 'simultaneo';
        p.t_operacion_min    = 60;
        p.factor_seg_caudal  = 1.10;
        p.factor_seg_volumen = 1.20;
        p.factor_localizadas = 1.25;
        p.v_max_principal    = 2.5;
        p.v_max_ramal        = 3.0;
        p.factor_traslape_cobertura = 0.85;   % cobertura útil
        p.exp_radio_presion  = 0.5;           % r(P)=r_nom·(P/P_nom)^exp  @CITA (límite de caudal)
        p.g                  = 9.81;
        p.rho                = 1000;
        p.costo_kWh_CLP      = 130;
        p.factor_arranque    = 1.25;
        p.n_bombas_paralelo_max = 3;
        p.HP_max_paralelo    = 2.0;
        p.costo_accesorios_paralelo = [0, 280000, 480000];

        % --- Disposición geométrica paramétrica (motor geometria_vivienda) ---
        p.disp = geometria_vivienda('default');
        geo0 = geometria_vivienda('construir', p);
        p.area_techo_m2     = geo0.area_techo_m2;     % derivados desde la geometría
        p.perimetro_m       = geo0.perimetro_m;
        p.area_perimetro_m2 = geo0.area_perimetro_m2;
    end

    function it = iteracion_default()
        it.n_techo_min      = 4;       it.n_techo_max      = 16;
        it.n_perimetro_min  = 4;       it.n_perimetro_max  = 16;
        it.DN_principal     = [32, 40, 50, 63];
        it.DN_ramal         = [20, 25, 32, 40];
        it.materiales       = {'PVC', 'HDPE'};
        it.criterio_optimo  = 'compuesto';
        it.pesos.costo      = 0.40;
        it.pesos.potencia   = 0.35;
        it.pesos.agua       = 0.25;
    end

    % ------------------------------------------------------
    %  TAB 1 — Vivienda y sistema  (disposición paramétrica + preview)
    % ------------------------------------------------------
    function crear_tab_vivienda(parent)
        g = uigridlayout(parent, [1 2]);
        g.ColumnWidth = {'1x', '1.1x'};
        g.Padding = [15 15 15 15]; g.ColumnSpacing = 18;

        % ===== Columna izquierda: disposición =====
        pL = uipanel(g, 'Title','Disposición de la vivienda (geometría paramétrica)', ...
                    'FontWeight','bold','BackgroundColor','white');
        pL.Layout.Column = 1;
        gL = uigridlayout(pL, [13 3]);
        gL.RowHeight = repmat({34}, 1, 13);
        gL.ColumnWidth = {200, '1x', 100};

        % Forma
        uilabel(gL, 'Text','Forma de la planta:','FontWeight','bold');
        dd_forma = uidropdown(gL, ...
            'Items',{'Rectangular','L','T'}, ...
            'ItemsData',{'rectangular','L','T'}, ...
            'Value', app.parametros.disp.forma, ...
            'ValueChangedFcn',@(src,~) cambiar_disp_dropdown('forma', src.Value));
        dd_forma.Layout.Row = 1; dd_forma.Layout.Column = [2 3];
        app.handles.dd_forma = dd_forma;

        % Dimensiones
        crear_slider(gL, 2, 'Largo (X) [m]',  'largo_m', 4, 30, app.parametros.disp.largo_m, '%.1f', 'disp');
        crear_slider(gL, 3, 'Ancho (Y) [m]',  'ancho_m', 3, 20, app.parametros.disp.ancho_m, '%.1f', 'disp');

        % Saliente (para L y T)
        crear_slider(gL, 4, 'Saliente: inicio X [m]', 'saliente_x_m',     0, 25, app.parametros.disp.saliente_x_m,     '%.1f', 'disp');
        crear_slider(gL, 5, 'Saliente: ancho [m]',    'saliente_ancho_m', 1, 15, app.parametros.disp.saliente_ancho_m, '%.1f', 'disp');
        crear_slider(gL, 6, 'Saliente: largo [m]',    'saliente_largo_m', 1, 12, app.parametros.disp.saliente_largo_m, '%.1f', 'disp');

        % Techo
        uilabel(gL, 'Text','Tipo de techo:','FontWeight','bold');
        dd_techo = uidropdown(gL, ...
            'Items',{'Dos aguas','Cuatro aguas','Plano'}, ...
            'ItemsData',{'dos_aguas','cuatro_aguas','plano'}, ...
            'Value', app.parametros.disp.tipo_techo, ...
            'ValueChangedFcn',@(src,~) cambiar_disp_dropdown('tipo_techo', src.Value));
        dd_techo.Layout.Row = 7; dd_techo.Layout.Column = [2 3];
        app.handles.dd_techo = dd_techo;

        uilabel(gL, 'Text','Cumbrera (dos aguas):','FontWeight','bold');
        dd_orient = uidropdown(gL, ...
            'Items',{'Horizontal','Vertical'}, ...
            'ItemsData',{'horizontal','vertical'}, ...
            'Value', app.parametros.disp.orientacion_cumbrera, ...
            'ValueChangedFcn',@(src,~) cambiar_disp_dropdown('orientacion_cumbrera', src.Value));
        dd_orient.Layout.Row = 8; dd_orient.Layout.Column = [2 3];
        app.handles.dd_orient = dd_orient;

        % Separación de aspersores (techo y perímetro por separado), franja y ventanas
        crear_slider(gL, 9,  'Separación aspersores TECHO [m]',     'sep_aspersores_m', 1.0, 5.0, app.parametros.disp.sep_aspersores_m, '%.1f', 'disp');
        crear_slider(gL, 10, 'Separación aspersores PERÍMETRO [m]', 'sep_perimetro_m',  1.0, 5.0, app.parametros.disp.sep_perimetro_m,  '%.1f', 'disp');
        crear_slider(gL, 11, 'Ancho franja defensa [m]',            'ancho_franja_m',   1.0, 5.0, app.parametros.ancho_franja_m,        '%.1f');
        crear_slider(gL, 12, 'N° de ventanas',                      'n_ventanas',       2, 12,   app.parametros.n_ventanas,             '%.0f');

        % Nebulizadores de ventana: opcionales en la evaluación
        cb_neb = uicheckbox(gL, 'Text','Incluir nebulizadores en ventanas', ...
            'Value', app.parametros.usar_nebulizadores, ...
            'ValueChangedFcn', @(src,~) cambiar_usar_neb(src.Value));
        cb_neb.Layout.Row = 13; cb_neb.Layout.Column = [1 3];
        app.handles.cb_neb = cb_neb;

        % ===== Columna derecha: longitudes + derivados + preview =====
        pR = uipanel(g, 'BorderType','none','BackgroundColor',[0.96 0.96 0.97]);
        pR.Layout.Column = 2;
        gR = uigridlayout(pR, [3 1]);
        gR.RowHeight = {230, 70, '1x'};
        gR.RowSpacing = 10; gR.Padding = [0 0 0 0];

        % --- Longitudes de tubería (trazado real: aducción + anillo + derivaciones) ---
        % El anillo perimetral sigue el contorno de la vivienda (L = perímetro).
        pLon = uipanel(gR, 'Title','Longitudes de tubería (aducción + anillo + derivaciones)', ...
                    'FontWeight','bold','BackgroundColor','white');
        pLon.Layout.Row = 1;
        gLon = uigridlayout(pLon, [4 3]);
        gLon.RowHeight = repmat({34}, 1, 4);
        gLon.ColumnWidth = {200, '1x', 100};
        crear_slider(gLon, 1, 'L aducción estanque→anillo [m]',  'L_aduccion_m',         1, 50, app.parametros.L_aduccion_m,         '%.1f');
        crear_slider(gLon, 2, 'L montante techo c/u [m]',        'L_montante_techo_m',   0.5, 8, app.parametros.L_montante_techo_m,   '%.1f');
        crear_slider(gLon, 3, 'L ramal perímetro c/u [m]',       'L_ramal_perim_unit_m', 0.5, 10, app.parametros.L_ramal_perim_unit_m, '%.1f');
        crear_slider(gLon, 4, 'L mangueras kit ventanas [m]',    'L_ramal_vent_m',       0, 40, app.parametros.L_ramal_vent_m,       '%.1f');

        % --- Derivados (solo lectura) ---
        pDer = uipanel(gR, 'Title','Derivados de la geometría', ...
                    'FontWeight','bold','BackgroundColor','white');
        pDer.Layout.Row = 2;
        gDer = uigridlayout(pDer, [1 4]);
        gDer.ColumnWidth = {'1x','1x','1x','1x'};
        app.handles.lbl_area_techo  = etiqueta_derivada(gDer, 'Área techo [m²]',     '—');
        app.handles.lbl_perimetro   = etiqueta_derivada(gDer, 'Perímetro [m]',       '—');
        app.handles.lbl_area_perim  = etiqueta_derivada(gDer, 'Área franja [m²]',    '—');
        app.handles.lbl_alto        = etiqueta_derivada(gDer, 'H estática techo [m]', ...
            sprintf('%.1f', app.parametros.L_montante_techo_m - app.parametros.z_agua_estanque_m));

        % --- Vista previa ---
        pPrev = uipanel(gR, 'Title','Vista previa de la planta y disposición', ...
                    'FontWeight','bold','BackgroundColor','white');
        pPrev.Layout.Row = 3;
        gPrev = uigridlayout(pPrev, [1 1]); gPrev.Padding = [5 5 5 5];
        app.handles.ax_preview = uiaxes(gPrev);
        axis(app.handles.ax_preview, 'equal');

        refrescar_geometria();
    end

    function lbl = etiqueta_derivada(parent, titulo, valor)
        p = uipanel(parent,'BackgroundColor',[0.98 0.98 1.0], ...
                    'BorderType','line','BorderColor',[0.85 0.88 0.95]);
        gg = uigridlayout(p,[2 1]); gg.RowHeight = {16,'1x'};
        gg.Padding = [6 3 6 3]; gg.RowSpacing = 2;
        uilabel(gg,'Text',titulo,'FontSize',10,'FontColor',[0.4 0.4 0.4]);
        lbl = uilabel(gg,'Text',valor,'FontSize',15,'FontWeight','bold', ...
                      'FontColor',[0.15 0.30 0.55]);
    end

    function cambiar_disp_dropdown(campo, valor)
        app.parametros.disp.(campo) = valor;
        refrescar_geometria();
        actualizar_estado(sprintf('Disposición: %s = %s', campo, valor));
    end

    function cambiar_usar_neb(valor)
        app.parametros.usar_nebulizadores = logical(valor);
        if valor
            actualizar_estado('Nebulizadores de ventana INCLUIDOS en la evaluación.');
        else
            actualizar_estado('Nebulizadores de ventana EXCLUIDOS de la evaluación (solo techo + perímetro).');
        end
    end

    function refrescar_geometria()
        % Construye la geometría desde la disposición actual, actualiza los
        % derivados (área/perímetro) en los parámetros y redibuja el preview.
        try
            d = app.parametros.disp;
            d.ancho_franja_m = app.parametros.ancho_franja_m;
            d.n_ventanas     = app.parametros.n_ventanas;
            geo = geometria_vivienda('construir', d);

            % Sincronizar derivados hacia los parámetros hidráulicos
            app.parametros.area_techo_m2     = geo.area_techo_m2;
            app.parametros.perimetro_m       = geo.perimetro_m;
            app.parametros.area_perimetro_m2 = geo.area_perimetro_m2;

            if isfield(app.handles,'lbl_area_techo')
                app.handles.lbl_area_techo.Text = sprintf('%.1f', geo.area_techo_m2);
                app.handles.lbl_perimetro.Text  = sprintf('%.1f', geo.perimetro_m);
                app.handles.lbl_area_perim.Text = sprintf('%.1f', geo.area_perimetro_m2);
            end

            dibujar_preview(geo, d);
        catch ME
            actualizar_estado(['Error geometría: ' ME.message]);
        end
    end

    function dibujar_preview(geo, d)
        ax = app.handles.ax_preview;
        cla(ax); hold(ax,'on'); axis(ax,'equal');

        % nº representativo de aspersores según la separación elegida.
        % Ambas zonas se distribuyen a lo largo del anillo perimetral
        % (los de techo suben por montantes desde el anillo).
        n_t = max(2, round(geo.perimetro_m / max(d.sep_aspersores_m,0.5)));
        n_p = max(2, round(geo.perimetro_m / max(d.sep_perimetro_m,0.5)));

        franja = geometria_vivienda('expandir', geo.contorno, d.ancho_franja_m);
        % Trazado real: los aspersores de techo van sobre MONTANTES que suben
        % desde el anillo perimetral (contorno), no sobre las cumbreras.
        pos_t  = geometria_vivienda('distribuir_perimetro', geo, n_t, 0);
        pos_p  = geometria_vivienda('distribuir_perimetro', geo, n_p, d.ancho_franja_m);
        pos_v  = geo.ventanas_centros;

        fill(ax, franja(:,1), franja(:,2), [0.95 0.92 0.80], ...
             'EdgeColor',[0.7 0.6 0.4],'LineStyle',':','FaceAlpha',0.5);
        fill(ax, geo.contorno(:,1), geo.contorno(:,2), [0.98 0.98 0.98], ...
             'EdgeColor','k','LineWidth',2);
        for k = 1:numel(geo.cumbreras)
            C = geo.cumbreras{k};
            plot(ax, C(:,1), C(:,2), '--', 'Color',[0.6 0.3 0.1], 'LineWidth',1.0);
        end
        for k = 1:numel(geo.ventanas)
            V = geo.ventanas{k};
            plot(ax, V(:,1), V(:,2), '-', 'Color',[0.20 0.45 0.75], 'LineWidth',3);
        end
        plot(ax, pos_t(:,1), pos_t(:,2), 'o', 'MarkerFaceColor',[0.95 0.45 0.10], ...
             'MarkerEdgeColor','k','MarkerSize',6);
        plot(ax, pos_p(:,1), pos_p(:,2), 's', 'MarkerFaceColor',[0.20 0.45 0.75], ...
             'MarkerEdgeColor','k','MarkerSize',6);
        if ~isempty(pos_v)
            plot(ax, pos_v(:,1), pos_v(:,2), '^', 'MarkerFaceColor',[0.30 0.75 0.55], ...
                 'MarkerEdgeColor','k','MarkerSize',8);
        end
        hold(ax,'off');
        grid(ax,'on');
        title(ax, sprintf('%s  %.1f×%.1f m  |  ~%d techo · ~%d perím · %d vent (sep≈%.1f m)', ...
              upper(d.forma), d.largo_m, d.ancho_m, n_t, n_p, size(pos_v,1), d.sep_aspersores_m), ...
              'FontSize',10);
        xlabel(ax,'X [m]'); ylabel(ax,'Y [m]');
    end

    % ------------------------------------------------------
    %  TAB 2 — Modelo de fuego (Rothermel/Byram → densidades y t_operación)
    % ------------------------------------------------------
    function crear_tab_fuego(parent)
        g = uigridlayout(parent, [1 2]);
        g.ColumnWidth = {'1x', '1x'};
        g.Padding = [15 15 15 15]; g.ColumnSpacing = 20;

        % ===== Izquierda: caso de combustible/ambiente =====
        pL = uipanel(g, 'Title','Caso de combustible y ambiente (Rothermel 1972 / Byram)', ...
                    'FontWeight','bold','BackgroundColor','white');
        pL.Layout.Column = 1;
        gL = uigridlayout(pL, [10 2]);
        gL.RowHeight = repmat({34}, 1, 10);
        gL.ColumnWidth = {240, '1x'};

        app.handles.fuego = struct();
        agregar_campo_fuego(gL, 'Carga de combustible w₀ [kg/m²]', 'w0_kgm2',       1.00, '%.2f');
        agregar_campo_fuego(gL, 'Relación sup/vol σ [1/m]',        'sav_1m',        5000, '%.0f');
        agregar_campo_fuego(gL, 'Altura del lecho δ [m]',          'delta_m',       0.50, '%.2f');
        agregar_campo_fuego(gL, 'Humedad del combustible Mf [-]',  'Mf',            0.08, '%.3f');
        agregar_campo_fuego(gL, 'Humedad de extinción Mx [-]',     'Mx',            0.30, '%.3f');
        agregar_campo_fuego(gL, 'Viento [m/s]',                    'viento_ms',     5.0,  '%.1f');
        agregar_campo_fuego(gL, 'Pendiente [tan]',                 'pendiente_tan', 0.0,  '%.2f');
        agregar_campo_fuego(gL, 'Distancia despejada a pared [m]', 'd_pared_m',     5.0,  '%.1f');

        uilabel(gL, 'Text','Tipo de fuego:', 'FontWeight','bold');
        app.handles.fuego.tipo = uidropdown(gL, ...
            'Items',{'Superficie','Copa'}, 'ItemsData',{'superficie','copa'}, ...
            'Value','superficie');

        uibutton(gL, 'Text','🔥 Calcular', ...
            'BackgroundColor',[0.85 0.45 0.15],'FontColor','white','FontWeight','bold', ...
            'ButtonPushedFcn',@(~,~) calcular_fuego_cb());
        uibutton(gL, 'Text','➡ Aplicar a criterios', ...
            'ButtonPushedFcn',@(~,~) aplicar_fuego_cb());

        % ===== Derecha: resultados =====
        pR = uipanel(g, 'Title','Resultados del modelo de fuego', ...
                    'FontWeight','bold','BackgroundColor','white');
        pR.Layout.Column = 2;
        gR = uigridlayout(pR, [1 1]); gR.Padding = [5 5 5 5];
        app.handles.fuego.salida = uitextarea(gR, 'Editable','off', ...
                                              'FontName','Consolas','FontSize',11);
        app.handles.fuego.salida.Value = {'Ingrese el caso y presione "Calcular".', '', ...
            'Las densidades y el tiempo de operación derivados se pueden', ...
            'enviar a la pestaña de Criterios con "Aplicar a criterios".'};

        function agregar_campo_fuego(parent_, etiqueta, campo, valor, fmt)
            uilabel(parent_, 'Text', etiqueta);
            app.handles.fuego.(campo) = uieditfield(parent_, 'numeric', ...
                'Value', valor, 'ValueDisplayFormat', fmt, 'HorizontalAlignment','right');
        end
    end

    function caso = leer_caso_fuego()
        h = app.handles.fuego;
        caso.nombre        = 'Caso GUI';
        caso.w0_kgm2       = h.w0_kgm2.Value;
        caso.sav_1m        = h.sav_1m.Value;
        caso.delta_m       = h.delta_m.Value;
        caso.Mf            = h.Mf.Value;
        caso.Mx            = h.Mx.Value;
        caso.viento_ms     = h.viento_ms.Value;
        caso.pendiente_tan = h.pendiente_tan.Value;
        caso.d_pared_m     = h.d_pared_m.Value;
        caso.tipo          = h.tipo.Value;
    end

    function calcular_fuego_cb()
        try
            r = calcular_fuego(leer_caso_fuego());
            app.handles.fuego.resultado = r;
            L = {};
            L{end+1} = sprintf('  Tipo de fuego: %s', r.tipo);
            if ~isempty(r.nota), L{end+1} = sprintf('  Nota: %s', r.nota); end
            L{end+1} = '';
            L{end+1} = sprintf('  ROS:               %.1f m/min', r.R_mmin);
            L{end+1} = sprintf('  Intensidad reacción: %.0f kW/m²', r.IR_kWm2);
            L{end+1} = sprintf('  Intensidad Byram:    %.0f kW/m', r.I_Byram_kWm);
            L{end+1} = sprintf('  Longitud de llama:   %.2f m', r.L_llama_m);
            L{end+1} = '';
            L{end+1} = sprintf('  q incidente techo:   %.1f kW/m²', r.q_inc_techo_kWm2);
            L{end+1} = sprintf('  q neto techo:        %.1f kW/m²', r.q_neto_techo_kWm2);
            L{end+1} = sprintf('  q neto perímetro:    %.1f kW/m²', r.q_neto_perim_kWm2);
            if r.ignicion_sin_proteccion
                L{end+1} = '  ⚠ Ignición SIN protección: SÍ';
            else
                L{end+1} = '  Ignición sin protección: no';
            end
            L{end+1} = '';
            L{end+1} = '  ── Salidas para el optimizador ──';
            L{end+1} = sprintf('  Densidad techo:      %.2f L/min/m²', r.densidad_techo_Lmin_m2);
            L{end+1} = sprintf('  Densidad perímetro:  %.2f L/min/m²', r.densidad_perimetro_Lmin_m2);
            L{end+1} = sprintf('  Tiempo de operación: %.0f min', r.t_operacion_min);
            app.handles.fuego.salida.Value = L;
            actualizar_estado('Modelo de fuego calculado.');
        catch ME
            uialert(fig, ['Error en el modelo de fuego: ' ME.message], 'Error','Icon','error');
        end
    end

    function aplicar_fuego_cb()
        if ~isfield(app.handles.fuego, 'resultado')
            uialert(fig, 'Primero presione "Calcular".', 'Atención','Icon','warning'); return;
        end
        r = app.handles.fuego.resultado;
        [vt, ct] = fijar_param_slider('densidad_techo_Lmin_m2',     r.densidad_techo_Lmin_m2);
        [vp, cp] = fijar_param_slider('densidad_perimetro_Lmin_m2', r.densidad_perimetro_Lmin_m2);
        [vo, co] = fijar_param_slider('t_operacion_min',            r.t_operacion_min);
        msg = sprintf('Aplicado a Criterios: densidad techo=%.2f, perímetro=%.2f, t_op=%.0f min', ...
                      vt, vp, vo);
        if ct || cp || co
            msg = [msg '  (algún valor se limitó al rango del control)'];
        end
        actualizar_estado(msg);
        uialert(fig, msg, 'Aplicado a criterios', 'Icon','success');
    end

    function [v, clamped] = fijar_param_slider(field, v0)
        sl = app.handles.(['sl_' field]);  ed = app.handles.(['ed_' field]);
        v  = max(sl.Limits(1), min(sl.Limits(2), v0));
        clamped = (v ~= v0);
        sl.Value = v;  ed.Value = v;  app.parametros.(field) = v;
    end

    % ------------------------------------------------------
    %  TAB 3 — Criterios y restricciones
    % ------------------------------------------------------
    function crear_tab_criterios(parent)
        g = uigridlayout(parent, [1 2]);
        g.ColumnWidth = {'1x', '1x'};
        g.Padding = [15 15 15 15]; g.ColumnSpacing = 20;

        pL = uipanel(g, 'Title','Criterios normativos (NFPA 1144 + IBHS/FireSmart)', ...
                    'FontWeight','bold','BackgroundColor','white');
        pL.Layout.Column = 1;
        gL = uigridlayout(pL, [7 3]);
        gL.RowHeight = repmat({36}, 1, 7);
        gL.ColumnWidth = {220, '1x', 100};

        crear_slider(gL, 1, 'Densidad techo [L/min/m²]',     'densidad_techo_Lmin_m2',     0.5, 4.0, 2.0, '%.2f');
        crear_slider(gL, 2, 'Densidad perímetro [L/min/m²]', 'densidad_perimetro_Lmin_m2', 0.3, 3.0, 1.0, '%.2f');
        crear_slider(gL, 3, 'Tiempo de operación [min]',     't_operacion_min',            30, 180, 60, '%.0f');

        lbl_mod = uilabel(gL, 'Text','Modo de activación:','FontWeight','bold');
        lbl_mod.Layout.Row = 4; lbl_mod.Layout.Column = 1;

        bg = uibuttongroup(gL,'BorderType','none','BackgroundColor','white');
        bg.Layout.Row = 4; bg.Layout.Column = [2 3];
        rb_sim = uiradiobutton(bg,'Text','Simultáneo (recomendado)',...
                                'Position',[10 8 200 22],'Value',true);
        rb_zon = uiradiobutton(bg,'Text','Zonal (comparativo)',...
                                'Position',[220 8 200 22]);
        bg.SelectionChangedFcn = @(~,evt) cambiar_modo(evt);
        app.handles.rb_sim = rb_sim; app.handles.rb_zon = rb_zon;

        crear_slider(gL, 5, 'Factor seguridad caudal',     'factor_seg_caudal',  1.0, 1.5, 1.10, '%.2f');
        crear_slider(gL, 6, 'Factor seguridad volumen',    'factor_seg_volumen', 1.0, 1.5, 1.20, '%.2f');
        crear_slider(gL, 7, 'Factor pérdidas localizadas', 'factor_localizadas', 1.05, 1.5, 1.25, '%.2f');

        pR = uipanel(g, 'Title','Restricciones hidráulicas y económicas', ...
                    'FontWeight','bold','BackgroundColor','white');
        pR.Layout.Column = 2;
        gR = uigridlayout(pR, [6 3]);
        gR.RowHeight = repmat({36}, 1, 6);
        gR.ColumnWidth = {220, '1x', 100};

        crear_slider(gR, 1, 'V máx tubería principal [m/s]','v_max_principal', 1.0, 3.5, 2.5, '%.2f');
        crear_slider(gR, 2, 'V máx ramales [m/s]',          'v_max_ramal',     1.5, 4.0, 3.0, '%.2f');
        crear_slider(gR, 3, 'Costo electricidad [CLP/kWh]', 'costo_kWh_CLP',   80, 300, 130, '%.0f');
        crear_slider(gR, 4, 'Factor de arranque bomba',     'factor_arranque', 1.0, 2.0, 1.25, '%.2f');

        lbl3 = uilabel(gR, 'Text', ...
            'NFPA 13: v máx en principal 2.5 m/s (admite hasta 3.0 m/s en sistemas especiales).', ...
            'FontAngle','italic','FontColor',[0.4 0.4 0.4]);
        lbl3.Layout.Row = 6; lbl3.Layout.Column = [1 3];
    end

    function cambiar_modo(evt)
        if startsWith(evt.NewValue.Text, 'Sim')
            app.parametros.modo_activacion = 'simultaneo';
        else
            app.parametros.modo_activacion = 'zonal';
        end
        actualizar_estado(sprintf('Modo: %s', app.parametros.modo_activacion));
    end

    % ------------------------------------------------------
    %  TAB 4 — Iteración y bombas
    % ------------------------------------------------------
    function crear_tab_iteracion(parent)
        g = uigridlayout(parent, [2 2]);
        g.ColumnWidth = {'1x', '1x'};
        g.RowHeight   = {'1x', '1x'};
        g.Padding = [15 15 15 15]; g.ColumnSpacing = 20; g.RowSpacing = 15;

        pNO = uipanel(g, 'Title','Rangos de cantidad de aspersores', ...
                      'FontWeight','bold','BackgroundColor','white');
        pNO.Layout.Row = 1; pNO.Layout.Column = 1;
        gNO = uigridlayout(pNO, [4 3]);
        gNO.RowHeight = repmat({36}, 1, 4);
        gNO.ColumnWidth = {200, '1x', 100};

        crear_slider(gNO, 1, 'N° aspersores TECHO — mín', 'n_techo_min',     2, 10, 4, '%.0f', 'iter');
        crear_slider(gNO, 2, 'N° aspersores TECHO — máx', 'n_techo_max',     6, 20, 16, '%.0f', 'iter');
        crear_slider(gNO, 3, 'N° aspersores PERÍM — mín', 'n_perimetro_min', 2, 10, 4, '%.0f', 'iter');
        crear_slider(gNO, 4, 'N° aspersores PERÍM — máx', 'n_perimetro_max', 6, 20, 16, '%.0f', 'iter');

        pNE = uipanel(g, 'Title','Diámetros y materiales a iterar', ...
                      'FontWeight','bold','BackgroundColor','white');
        pNE.Layout.Row = 1; pNE.Layout.Column = 2;
        gNE = uigridlayout(pNE, [5 2]);
        gNE.RowHeight = repmat({36}, 1, 5);
        gNE.ColumnWidth = {180, '1x'};

        uilabel(gNE, 'Text','DN principal [mm]:','FontWeight','bold');
        cb_panel1 = uipanel(gNE, 'BorderType','none','BackgroundColor','white');
        crear_checkboxes_dn(cb_panel1, [25 32 40 50 63 75], [0 1 1 1 1 0], 'DN_principal');

        uilabel(gNE, 'Text','DN ramales [mm]:','FontWeight','bold');
        cb_panel2 = uipanel(gNE, 'BorderType','none','BackgroundColor','white');
        crear_checkboxes_dn(cb_panel2, [15 20 25 32 40], [0 1 1 1 1], 'DN_ramal');

        uilabel(gNE, 'Text','Materiales:','FontWeight','bold');
        cb_panel3 = uipanel(gNE, 'BorderType','none','BackgroundColor','white');
        crear_checkboxes_mat(cb_panel3, {'PVC','HDPE','Cobre'}, [1 1 0]);

        pSO = uipanel(g, 'Title','Bombas en paralelo (estrategia ahorro)', ...
                      'FontWeight','bold','BackgroundColor','white');
        pSO.Layout.Row = 2; pSO.Layout.Column = 1;
        gSO = uigridlayout(pSO, [5 3]);
        gSO.RowHeight = repmat({36}, 1, 5);
        gSO.ColumnWidth = {220, '1x', 100};

        crear_slider(gSO, 1, 'N° máximo bombas en paralelo','n_bombas_paralelo_max', 1, 4, 3, '%.0f');
        crear_slider(gSO, 2, 'HP máximo para paralelo',     'HP_max_paralelo',       0.5, 5.0, 2.0, '%.1f');
        crear_slider(gSO, 3, 'Accesorios 2 bombas [CLP]',   'costo_acc_2',           0, 1000000, 280000, '%.0f', 'acc');
        crear_slider(gSO, 4, 'Accesorios 3 bombas [CLP]',   'costo_acc_3',           0, 1500000, 480000, '%.0f', 'acc');

        lbl4 = uilabel(gSO, 'Text', ...
            'Manifold, válvulas check y controlador alternante. Valores típicos mercado chileno.', ...
            'FontAngle','italic','FontColor',[0.4 0.4 0.4]);
        lbl4.Layout.Row = 5; lbl4.Layout.Column = [1 3];

        pSE = uipanel(g, 'Title','Función objetivo / criterio de optimización', ...
                      'FontWeight','bold','BackgroundColor','white');
        pSE.Layout.Row = 2; pSE.Layout.Column = 2;
        gSE = uigridlayout(pSE, [5 2]);
        gSE.RowHeight = repmat({36}, 1, 5);
        gSE.ColumnWidth = {180, '1x'};

        uilabel(gSE, 'Text','Criterio:','FontWeight','bold');
        dd = uidropdown(gSE, ...
            'Items',{'Compuesto (ponderado)','Costo total','Potencia bomba','Volumen estanque'}, ...
            'ItemsData',{'compuesto','costo','potencia','agua'}, ...
            'Value','compuesto', ...
            'ValueChangedFcn',@(src,~) cambiar_criterio(src.Value));
        app.handles.dd_criterio = dd;

        uilabel(gSE, 'Text','');
        uilabel(gSE, 'Text','Pesos (solo modo compuesto):', ...
                'FontAngle','italic','FontColor',[0.4 0.4 0.4]);

        crear_slider(gSE, 3, 'Peso costo',     'peso_costo',    0, 1, 0.40, '%.2f', 'peso');
        crear_slider(gSE, 4, 'Peso potencia',  'peso_potencia', 0, 1, 0.35, '%.2f', 'peso');
        crear_slider(gSE, 5, 'Peso agua',      'peso_agua',     0, 1, 0.25, '%.2f', 'peso');
    end

    function cambiar_criterio(val)
        app.iteracion.criterio_optimo = val;
        actualizar_estado(sprintf('Criterio: %s', val));
    end

    % ------------------------------------------------------
    %  TAB 5 — Resultados
    % ------------------------------------------------------
    function crear_tab_resultados(parent)
        g = uigridlayout(parent, [2 2]);
        g.ColumnWidth = {'1.3x', '1x'};
        g.RowHeight   = {'1x', '1x'};
        g.Padding = [15 15 15 15]; g.ColumnSpacing = 15; g.RowSpacing = 15;

        % --- Tabla top-10 (uitable en uigridlayout) ---
        pNO = uipanel(g, 'Title','Top-10 configuraciones','FontWeight','bold','BackgroundColor','white');
        pNO.Layout.Row = 1; pNO.Layout.Column = 1;
        gNO = uigridlayout(pNO, [1 1]); gNO.Padding = [2 2 2 2];
        app.handles.tabla = uitable(gNO, 'ColumnEditable',false);

        % --- Detalle óptima (uitextarea en uigridlayout) ---
        pNE = uipanel(g, 'Title','Configuración óptima — detalle','FontWeight','bold','BackgroundColor','white');
        pNE.Layout.Row = 1; pNE.Layout.Column = 2;
        gNE = uigridlayout(pNE, [2 1]); gNE.Padding = [5 5 5 5];
        gNE.RowHeight = {30, '1x'};
        b_lim = uibutton(gNE,'Text','🔧 Límite de caudal → objetivo de bomba', ...
            'BackgroundColor',[0.85 0.55 0.20],'FontColor','white','FontWeight','bold', ...
            'ButtonPushedFcn',@(~,~) analizar_limite_caudal());
        b_lim.Layout.Row = 1;
        app.handles.textarea_optima = uitextarea(gNE, 'Editable','off', ...
                                                  'FontName','Consolas','FontSize',11);
        app.handles.textarea_optima.Layout.Row = 2;
        app.handles.textarea_optima.Value = {'Presione "Ejecutar análisis" para obtener resultados.'};

        % --- Pareto integrado (uiaxes en uigridlayout) ---
        pSO = uipanel(g, 'Title','Frontera de Pareto (costo vs potencia)','FontWeight','bold','BackgroundColor','white');
        pSO.Layout.Row = 2; pSO.Layout.Column = 1;
        gSO = uigridlayout(pSO, [1 1]); gSO.Padding = [5 5 5 5];
        app.handles.ax_pareto = uiaxes(gSO);
        xlabel(app.handles.ax_pareto,'Potencia bomba [HP]');
        ylabel(app.handles.ax_pareto,'Costo total [miles CLP]');
        grid(app.handles.ax_pareto,'on'); grid(app.handles.ax_pareto,'minor');

        % --- KPIs ---
        pSE = uipanel(g, 'Title','Indicadores clave','FontWeight','bold','BackgroundColor','white');
        pSE.Layout.Row = 2; pSE.Layout.Column = 2;
        gSE = uigridlayout(pSE, [4 2]);
        gSE.RowHeight = repmat({'1x'}, 1, 4);

        app.handles.kpi = struct();
        app.handles.kpi.config_viables = crear_kpi(gSE, 1, 1, 'Configs viables',     '—');
        app.handles.kpi.Q_optima       = crear_kpi(gSE, 1, 2, 'Q diseño [L/min]',    '—');
        app.handles.kpi.HMT_optima     = crear_kpi(gSE, 2, 1, 'HMT [m.c.a.]',        '—');
        app.handles.kpi.HP_optima      = crear_kpi(gSE, 2, 2, 'Potencia total [HP]', '—');
        app.handles.kpi.V_estanque     = crear_kpi(gSE, 3, 1, 'V estanque [m³]',     '—');
        app.handles.kpi.costo_total    = crear_kpi(gSE, 3, 2, 'Costo [CLP]',         '—');
        app.handles.kpi.n_bombas       = crear_kpi(gSE, 4, 1, 'N° bombas',           '—');
        app.handles.kpi.zona_crit      = crear_kpi(gSE, 4, 2, 'Zona crítica',        '—');
    end

    function lbl_val = crear_kpi(parent, row, col, titulo, valor)
        p = uipanel(parent,'BackgroundColor',[0.98 0.98 1.0], ...
                    'BorderType','line','BorderColor',[0.85 0.88 0.95]);
        p.Layout.Row = row; p.Layout.Column = col;
        gg = uigridlayout(p, [2 1]);
        gg.RowHeight = {16, '1x'};
        gg.Padding = [8 4 8 4]; gg.RowSpacing = 2;
        uilabel(gg, 'Text',titulo, 'FontSize',10, 'FontColor',[0.4 0.4 0.4]);
        lbl_val = uilabel(gg, 'Text',valor, 'FontSize',15, 'FontWeight','bold', ...
                          'FontColor',[0.15 0.30 0.55]);
    end

    % ------------------------------------------------------
    %  TAB 6 — Editor de Bases de Datos
    % ------------------------------------------------------
    function crear_tab_editor_bds(parent)
        g = uigridlayout(parent, [2 1]);
        g.RowHeight = {40, '1x'};
        g.Padding = [10 10 10 10]; g.RowSpacing = 8;

        % Barra de botones
        bar = uipanel(g, 'BorderType','none','BackgroundColor',[0.92 0.94 0.97]);
        bar.Layout.Row = 1;
        gb = uigridlayout(bar, [1 5]);
        gb.ColumnWidth = {'1x','1x','1x','1x','2x'};
        gb.Padding = [5 4 5 4]; gb.ColumnSpacing = 6;

        b1 = uibutton(gb,'Text','💾 Guardar cambios al Excel', ...
                      'ButtonPushedFcn',@(~,~) guardar_bd_actual());
        b1.Layout.Column = 1;

        b2 = uibutton(gb,'Text','📂 Recargar desde Excel', ...
                      'ButtonPushedFcn',@(~,~) cargar_BDs());
        b2.Layout.Column = 2;

        b3 = uibutton(gb,'Text','➕ Agregar fila', ...
                      'ButtonPushedFcn',@(~,~) agregar_fila_bd());
        b3.Layout.Column = 3;

        b4 = uibutton(gb,'Text','🗑 Eliminar fila seleccionada', ...
                      'ButtonPushedFcn',@(~,~) eliminar_fila_bd());
        b4.Layout.Column = 4;

        lbl = uilabel(gb,'Text','Edita las celdas directamente. Los cambios se aplican al ejecutar el análisis.', ...
                      'FontAngle','italic','FontColor',[0.4 0.4 0.4]);
        lbl.Layout.Column = 5;

        % Sub-pestanas
        tg_bd = uitabgroup(g);
        tg_bd.Layout.Row = 2;
        app.handles.tg_bd = tg_bd;

        tab_asp = uitab(tg_bd,'Title','  Aspersores  ');
        tab_tub = uitab(tg_bd,'Title','  Tuberías  ');
        tab_bom = uitab(tg_bd,'Title','  Bombas  ');

        % Tablas (se popularán al cargar BDs)
        ga = uigridlayout(tab_asp,[1 1]); ga.Padding = [5 5 5 5];
        app.handles.tabla_asp = uitable(ga, 'ColumnEditable',true, ...
            'CellEditCallback',@(src,evt) bd_celda_editada('aspersores', evt));

        gt = uigridlayout(tab_tub,[1 1]); gt.Padding = [5 5 5 5];
        app.handles.tabla_tub = uitable(gt, 'ColumnEditable',true, ...
            'CellEditCallback',@(src,evt) bd_celda_editada('tuberias', evt));

        gbb = uigridlayout(tab_bom,[1 1]); gbb.Padding = [5 5 5 5];
        app.handles.tabla_bom = uitable(gbb, 'ColumnEditable',true, ...
            'CellEditCallback',@(src,evt) bd_celda_editada('bombas', evt));
    end

    function refrescar_tablas_bd()
        if isempty(app.BD), return; end
        app.handles.tabla_asp.Data = app.BD.aspersores;
        app.handles.tabla_tub.Data = app.BD.tuberias;
        app.handles.tabla_bom.Data = app.BD.bombas;
    end

    function bd_celda_editada(tipo, evt)
        % Aplica la edición al BD en memoria respetando el tipo de la columna
        % (numérica o de texto), evitando corromper columnas numéricas.
        try
            r = evt.Indices(1);  c = evt.Indices(2);
            T  = app.BD.(tipo);
            vn = T.Properties.VariableNames{c};
            if iscell(T.(vn))
                T.(vn){r} = evt.NewData;
            else
                T.(vn)(r) = evt.NewData;
            end
            % Si se editan las curvas de bomba, reparsear los vectores numéricos
            if strcmp(tipo,'bombas')
                if strcmp(vn,'Curva_Q_Lmin')
                    T.Q_curva{r} = str2double(strsplit(evt.NewData, ';'));
                elseif strcmp(vn,'Curva_H_m')
                    T.H_curva{r} = str2double(strsplit(evt.NewData, ';'));
                end
            end
            app.BD.(tipo) = T;
            actualizar_estado(sprintf('Editado %s[%d,%d]. Recuerde guardar al Excel.', tipo, r, c));
        catch ME
            actualizar_estado(['Error en edición: ' ME.message]);
        end
    end

    function guardar_bd_actual()
        % Detecta cual sub-pestana esta activa y guarda la BD correspondiente al Excel
        sel = app.handles.tg_bd.SelectedTab.Title;
        try
            if contains(sel, 'Aspersores')
                writetable(app.BD.aspersores, 'BD_Aspersores.xlsx', 'Sheet','Aspersores');
                actualizar_estado('✓ BD_Aspersores.xlsx guardado');
            elseif contains(sel, 'Tuberías')
                writetable(app.BD.tuberias, 'BD_Tuberias.xlsx', 'Sheet','Tuberias');
                actualizar_estado('✓ BD_Tuberias.xlsx guardado');
            elseif contains(sel, 'Bombas')
                % Excluir Q_curva, H_curva (son derivados)
                T = app.BD.bombas;
                T.Q_curva = []; T.H_curva = [];
                writetable(T, 'BD_Bombas.xlsx', 'Sheet','Bombas');
                actualizar_estado('✓ BD_Bombas.xlsx guardado');
            end
            uialert(fig,'Cambios guardados al archivo Excel.','Guardado','Icon','success');
        catch ME
            uialert(fig,['Error al guardar: ' ME.message],'Error','Icon','error');
        end
    end

    function agregar_fila_bd()
        sel = app.handles.tg_bd.SelectedTab.Title;
        if contains(sel,'Aspersores')
            nueva = app.BD.aspersores(1,:); nueva.ID{1} = sprintf('ASP-%03d', height(app.BD.aspersores)+1);
            app.BD.aspersores = [app.BD.aspersores; nueva];
        elseif contains(sel,'Tuberías')
            nueva = app.BD.tuberias(1,:); nueva.ID{1} = sprintf('TUB-%03d', height(app.BD.tuberias)+1);
            app.BD.tuberias = [app.BD.tuberias; nueva];
        else
            nueva = app.BD.bombas(1,:); nueva.ID{1} = sprintf('BOM-%03d', height(app.BD.bombas)+1);
            app.BD.bombas = [app.BD.bombas; nueva];
        end
        refrescar_tablas_bd();
        actualizar_estado('Fila agregada. Edite los valores y guarde al Excel.');
    end

    function eliminar_fila_bd()
        sel = app.handles.tg_bd.SelectedTab.Title;
        if contains(sel,'Aspersores')
            t = app.handles.tabla_asp;
        elseif contains(sel,'Tuberías')
            t = app.handles.tabla_tub;
        else
            t = app.handles.tabla_bom;
        end

        if isempty(t.Selection)
            uialert(fig,'Seleccione primero una fila en la tabla.','Atención','Icon','warning');
            return;
        end

        row = t.Selection(1);
        if contains(sel,'Aspersores'),  app.BD.aspersores(row,:) = [];
        elseif contains(sel,'Tuberías'),app.BD.tuberias(row,:) = [];
        else,                            app.BD.bombas(row,:) = [];
        end
        refrescar_tablas_bd();
        actualizar_estado(sprintf('Fila %d eliminada.', row));
    end

    % ------------------------------------------------------
    %  TAB 7 — Comparador de escenarios
    % ------------------------------------------------------
    function crear_tab_comparador(parent)
        g = uigridlayout(parent, [2 1]);
        g.RowHeight = {40, '1x'};
        g.Padding = [10 10 10 10]; g.RowSpacing = 8;

        bar = uipanel(g, 'BorderType','none','BackgroundColor',[0.92 0.94 0.97]);
        bar.Layout.Row = 1;
        gb = uigridlayout(bar, [1 3]);
        gb.ColumnWidth = {'1x','1x','3x'};
        gb.Padding = [5 4 5 4]; gb.ColumnSpacing = 6;

        b1 = uibutton(gb,'Text','📌 Guardar escenario actual', ...
                      'BackgroundColor',[0.85 0.55 0.30],'FontColor','white','FontWeight','bold', ...
                      'ButtonPushedFcn',@(~,~) guardar_escenario());
        b1.Layout.Column = 1;

        b2 = uibutton(gb,'Text','🗑 Limpiar todos', ...
                      'ButtonPushedFcn',@(~,~) limpiar_escenarios());
        b2.Layout.Column = 2;

        lbl = uilabel(gb,'Text','Guarda hasta 3 escenarios después de ejecutar para compararlos lado a lado.', ...
                      'FontAngle','italic','FontColor',[0.4 0.4 0.4]);
        lbl.Layout.Column = 3;

        p = uipanel(g,'Title','Escenarios guardados','FontWeight','bold','BackgroundColor','white');
        p.Layout.Row = 2;
        gp = uigridlayout(p,[1 1]); gp.Padding = [5 5 5 5];
        app.handles.tabla_compar = uitable(gp, 'ColumnEditable',false);

        actualizar_tabla_comparador();
    end

    function guardar_escenario()
        if isempty(app.resultados) || isempty(app.resultados.viables)
            uialert(fig,'Primero ejecute un análisis con resultados viables.','Atención','Icon','warning');
            return;
        end
        if numel(app.escenarios) >= 3
            uialert(fig,'Ya hay 3 escenarios. Elimine alguno con "Limpiar todos" antes de agregar.', ...
                    'Atención','Icon','warning');
            return;
        end

        % Pedir nombre
        nombre = char(inputdlg('Nombre del escenario:','Guardar escenario',[1 50], ...
                               {sprintf('Escenario %d', numel(app.escenarios)+1)}));
        if isempty(nombre), return; end

        esc = struct();
        esc.nombre   = nombre;
        esc.fecha    = datestr(now,'yyyy-mm-dd HH:MM');
        esc.parametros = app.parametros;
        esc.iteracion  = app.iteracion;
        esc.optima     = app.resultados.viables(1,:);
        esc.n_viables  = height(app.resultados.viables);

        app.escenarios{end+1} = esc;
        actualizar_tabla_comparador();
        actualizar_estado(sprintf('Escenario "%s" guardado (total: %d)', nombre, numel(app.escenarios)));
    end

    function limpiar_escenarios()
        if isempty(app.escenarios), return; end
        sel = uiconfirm(fig,'¿Eliminar todos los escenarios guardados?','Confirmar', ...
                        'Options',{'Sí','Cancelar'},'DefaultOption',2,'CancelOption',2);
        if strcmp(sel,'Sí')
            app.escenarios = {};
            actualizar_tabla_comparador();
            actualizar_estado('Escenarios limpiados.');
        end
    end

    function actualizar_tabla_comparador()
        if isempty(app.escenarios)
            app.handles.tabla_compar.Data = ...
                cell2table({'(sin escenarios guardados)'}, 'VariableNames',{'Estado'});
            return;
        end

        % Construir tabla comparativa: filas = atributos, columnas = escenarios
        attrs = {'Nombre','Fecha','Modo','Aspersores techo','Aspersores perímetro', ...
                 'Diámetro principal','Caudal diseño [L/min]','HMT [m]', ...
                 'Bomba','N° bombas','Potencia total [HP]', ...
                 'Volumen estanque [m³]','Costo total [CLP]','Score'};
        n_esc = numel(app.escenarios);
        datos = cell(numel(attrs), n_esc);
        names = cell(1, n_esc);

        for i = 1:n_esc
            esc = app.escenarios{i};
            names{i} = matlab.lang.makeValidName(esc.nombre);
            o = esc.optima;
            datos{1,i}  = esc.nombre;
            datos{2,i}  = esc.fecha;
            datos{3,i}  = esc.parametros.modo_activacion;
            datos{4,i}  = sprintf('%d × %s', o.n_techo, o.asp_techo{1});
            datos{5,i}  = sprintf('%d × %s', o.n_perim, o.asp_perim{1});
            datos{6,i}  = sprintf('DN%d (%s)', o.DN_princ_mm, o.material_princ{1});
            datos{7,i}  = sprintf('%.0f', o.Q_diseno_Lmin);
            datos{8,i}  = sprintf('%.1f', o.HMT_m);
            datos{9,i}  = o.bomba_modelo{1};
            datos{10,i} = sprintf('%d', o.n_bombas);
            datos{11,i} = sprintf('%.1f', o.P_HP);
            datos{12,i} = sprintf('%.1f', o.V_estanque_m3);
            datos{13,i} = formato_miles(o.costo_total_CLP);
            datos{14,i} = sprintf('%.4f', o.score);
        end

        T = cell2table(datos, 'VariableNames', names, 'RowNames', attrs);
        app.handles.tabla_compar.Data = T;
    end

    % ------------------------------------------------------
    %  FOOTER (botones)
    % ------------------------------------------------------
    function crear_footer(parent)
        g = uigridlayout(parent, [2 9]);
        g.RowHeight = {'1x', 20};
        g.ColumnWidth = repmat({'1x'}, 1, 9);
        g.Padding = [10 6 10 6]; g.ColumnSpacing = 6; g.RowSpacing = 4;

        b1 = uibutton(g,'Text','▶  EJECUTAR ANÁLISIS', ...
            'BackgroundColor',[0.20 0.60 0.30],'FontColor','white', ...
            'FontSize',13,'FontWeight','bold', ...
            'ButtonPushedFcn',@(~,~) ejecutar_analisis());
        b1.Layout.Row = 1; b1.Layout.Column = [1 2];

        b2 = uibutton(g,'Text','📊 Gráficos', ...
            'ButtonPushedFcn',@(~,~) abrir_graficos());
        b2.Layout.Row = 1; b2.Layout.Column = 3;

        b3 = uibutton(g,'Text','📐 Layout', ...
            'ButtonPushedFcn',@(~,~) abrir_layout());
        b3.Layout.Row = 1; b3.Layout.Column = 4;

        b4 = uibutton(g,'Text','💾 Excel', ...
            'ButtonPushedFcn',@(~,~) exportar_excel());
        b4.Layout.Row = 1; b4.Layout.Column = 5;

        b5 = uibutton(g,'Text','📄 Generar EPANET', ...
            'BackgroundColor',[0.30 0.50 0.75],'FontColor','white','FontWeight','bold', ...
            'ButtonPushedFcn',@(~,~) generar_epanet());
        b5.Layout.Row = 1; b5.Layout.Column = 6;

        b6 = uibutton(g,'Text','💼 Guardar config', ...
            'ButtonPushedFcn',@(~,~) guardar_config());
        b6.Layout.Row = 1; b6.Layout.Column = 7;

        b7 = uibutton(g,'Text','📂 Cargar config', ...
            'ButtonPushedFcn',@(~,~) cargar_config());
        b7.Layout.Row = 1; b7.Layout.Column = 8;

        b8 = uibutton(g,'Text','↺ Reset', ...
            'ButtonPushedFcn',@(~,~) reset_defaults());
        b8.Layout.Row = 1; b8.Layout.Column = 9;

        lbl = uilabel(g,'Text','Listo. Configure los parámetros y presione Ejecutar análisis.', ...
                      'FontColor',[0.2 0.2 0.2],'FontSize',10);
        lbl.Layout.Row = 2; lbl.Layout.Column = [1 9];
        app.handles.lbl_estado = lbl;
    end

    % ------------------------------------------------------
    %  HELPERS DE WIDGETS
    % ------------------------------------------------------
    function crear_slider(parent, row, label, field, vmin, vmax, vdef, fmt, dest)
        if nargin < 9, dest = 'param'; end

        lbl = uilabel(parent,'Text',label);
        lbl.Layout.Row = row; lbl.Layout.Column = 1;

        sl = uislider(parent,'Limits',[vmin vmax],'Value',vdef, ...
                      'MajorTicks',[],'MinorTicks',[]);
        sl.Layout.Row = row; sl.Layout.Column = 2;

        ed = uieditfield(parent,'numeric','Value',vdef, ...
                         'ValueDisplayFormat',fmt,'HorizontalAlignment','right');
        ed.Layout.Row = row; ed.Layout.Column = 3;

        sl.ValueChangingFcn = @(src,evt) sliderChanging(evt.Value, ed, field, dest);
        ed.ValueChangedFcn  = @(src,~)   editChanged(src.Value, sl, field, dest);

        app.handles.(['sl_' field]) = sl;
        app.handles.(['ed_' field]) = ed;
    end

    function sliderChanging(v, ed, field, dest)
        ed.Value = v;
        propagar_a_app(field, v, dest);
    end

    function editChanged(v, sl, field, dest)
        v = max(sl.Limits(1), min(sl.Limits(2), v));
        sl.Value = v;
        propagar_a_app(field, v, dest);
    end

    function propagar_a_app(field, val, dest)
        switch dest
            case 'param'
                if isfield(app.parametros, field)
                    if strcmp(field, 'n_ventanas'), val = round(val); end
                    app.parametros.(field) = val;
                    % La franja y el nº de ventanas afectan la geometría
                    if any(strcmp(field, {'ancho_franja_m','n_ventanas'}))
                        refrescar_geometria();
                    end
                    % El montante de techo define la altura estática (derivado)
                    if strcmp(field, 'L_montante_techo_m') && isfield(app.handles,'lbl_alto')
                        app.handles.lbl_alto.Text = sprintf('%.1f', ...
                            val - app.parametros.z_agua_estanque_m);
                    end
                end
            case 'disp'
                if isfield(app.parametros.disp, field)
                    app.parametros.disp.(field) = val;
                    refrescar_geometria();
                end
            case 'iter'
                if isfield(app.iteracion, field)
                    app.iteracion.(field) = round(val);
                end
            case 'peso'
                f = strrep(field,'peso_','');
                app.iteracion.pesos.(f) = val;
            case 'acc'
                idx = str2double(field(end));
                v = app.parametros.costo_accesorios_paralelo;
                if idx <= numel(v), v(idx) = val; end
                app.parametros.costo_accesorios_paralelo = v;
        end
    end

    function crear_checkboxes_dn(panel, valores, defaults, var_name)
        for i = 1:numel(valores)
            cb = uicheckbox(panel,'Text',sprintf('DN%d',valores(i)), ...
                'Value',defaults(i),'Position',[10+(i-1)*65, 8, 60, 22]);
            cb.ValueChangedFcn = @(~,~) actualizar_dn(var_name);
            app.handles.(sprintf('cb_%s_%d', var_name, valores(i))) = cb;
        end
        app.handles.(['valores_' var_name]) = valores;
    end

    function actualizar_dn(var_name)
        valores = app.handles.(['valores_' var_name]);
        sel = [];
        for i = 1:numel(valores)
            cb = app.handles.(sprintf('cb_%s_%d', var_name, valores(i)));
            if cb.Value, sel(end+1) = valores(i); end
        end
        app.iteracion.(var_name) = sel;
    end

    function crear_checkboxes_mat(panel, materiales, defaults)
        for i = 1:numel(materiales)
            cb = uicheckbox(panel,'Text',materiales{i}, ...
                'Value',defaults(i),'Position',[10+(i-1)*80, 8, 70, 22]);
            cb.ValueChangedFcn = @(~,~) actualizar_materiales();
            app.handles.(sprintf('cb_mat_%s', materiales{i})) = cb;
        end
        app.handles.lista_materiales = materiales;
    end

    function actualizar_materiales()
        sel = {};
        for i = 1:numel(app.handles.lista_materiales)
            m = app.handles.lista_materiales{i};
            if app.handles.(['cb_mat_' m]).Value
                sel{end+1} = m;
            end
        end
        app.iteracion.materiales = sel;
    end

    % ------------------------------------------------------
    %  ACCIONES (callbacks)
    % ------------------------------------------------------
    function cargar_BDs()
        try
            actualizar_estado('Cargando bases de datos...'); drawnow;
            app.BD = cargar_BD('BD_Aspersores.xlsx','BD_Tuberias.xlsx','BD_Bombas.xlsx');
            refrescar_tablas_bd();
            actualizar_estado(sprintf(...
                'BDs cargadas: %d aspersores, %d tuberías, %d bombas.', ...
                height(app.BD.aspersores), height(app.BD.tuberias), height(app.BD.bombas)));
        catch ME
            actualizar_estado(['Error cargando BDs: ' ME.message]);
            uialert(fig,['No se pudieron cargar las BD: ' ME.message newline ...
                          'Verifique que los archivos Excel estén en la carpeta.'], ...
                    'Error','Icon','error');
        end
    end

    function ejecutar_analisis()
        if isempty(app.BD)
            uialert(fig,'Cargue primero las bases de datos.','Atención','Icon','warning'); return;
        end
        if isempty(app.iteracion.DN_principal) || isempty(app.iteracion.DN_ramal)
            uialert(fig,'Seleccione al menos un diámetro para principal y ramal.','Atención','Icon','warning'); return;
        end
        if isempty(app.iteracion.materiales)
            uialert(fig,'Seleccione al menos un material.','Atención','Icon','warning'); return;
        end

        actualizar_estado('Ejecutando análisis... (puede tomar varios segundos)');
        drawnow;

        try
            tic;
            app.resultados = iterar_configuraciones(app.BD, app.parametros, app.iteracion);
            t_iter = toc;

            n_viables = height(app.resultados.viables);
            actualizar_estado(sprintf('Análisis completo: %d viables de %d en %.1f s', ...
                n_viables, app.resultados.n_evaluadas, t_iter));

            if n_viables == 0
                uialert(fig,['Ninguna configuración resultó viable. Revise: rangos de aspersores, ' ...
                              'diámetros disponibles, velocidad máxima, o densidades requeridas.'], ...
                        'Sin soluciones','Icon','warning');
                return;
            end
            mostrar_resultados();
        catch ME
            actualizar_estado(['Error: ' ME.message]);
            uialert(fig,['Error durante la iteración: ' newline ME.message],'Error','Icon','error');
        end
    end

    function mostrar_resultados()
        V = app.resultados.viables;
        n_top = min(10, height(V));
        top = V(1:n_top, :);

        T = table(top.config_id, top.n_techo, top.n_perim, top.n_vent, ...
                  top.DN_princ_mm, top.Q_diseno_Lmin, top.HMT_m, ...
                  top.bomba_modelo, top.n_bombas, top.P_HP, ...
                  top.V_estanque_m3, top.costo_total_CLP, top.score, ...
                  'VariableNames',{'ID','N_T','N_P','N_V','DN','Q_Lmin','HMT_m', ...
                                   'Bomba','N_b','P_HP','V_m3','Costo','Score'});
        app.handles.tabla.Data = T;

        o = V(1,:);
        lines = {};
        lines{end+1} = '═══════════════════════════════════════════════';
        lines{end+1} = '  CONFIGURACIÓN ÓPTIMA RECOMENDADA';
        lines{end+1} = '═══════════════════════════════════════════════';
        lines{end+1} = '';
        lines{end+1} = sprintf('  Aspersores techo:     %d × %s', o.n_techo, o.asp_techo{1});
        lines{end+1} = sprintf('  Aspersores perímetro: %d × %s', o.n_perim, o.asp_perim{1});
        if o.n_vent > 0
            lines{end+1} = sprintf('  Nebulizadores vent.:  %d × %s', o.n_vent,  o.asp_vent{1});
        else
            lines{end+1} = '  Nebulizadores vent.:  (excluidos de esta evaluación)';
        end
        lines{end+1} = sprintf('  Diámetro principal:   DN%d (%s)', o.DN_princ_mm, o.material_princ{1});
        lines{end+1} = sprintf('  Diámetro ramales:     DN%d (%s)', o.DN_ramal_mm, o.material_ramal{1});
        lines{end+1} = '';
        lines{end+1} = sprintf('  Caudal de diseño:     %.1f L/min', o.Q_diseno_Lmin);
        lines{end+1} = sprintf('    └ zona crítica:     %s', o.zona_critica{1});
        lines{end+1} = sprintf('  HMT requerida:        %.1f m.c.a.', o.HMT_m);
        lines{end+1} = sprintf('  Presión mín. bomba:   %.2f bar', o.HMT_m/10.197);
        lines{end+1} = sprintf('  v principal:          %.2f m/s', o.v_principal_ms);
        lines{end+1} = '';
        if o.n_bombas == 1
            lines{end+1} = sprintf('  Bomba:                %s', o.bomba_modelo{1});
        else
            lines{end+1} = sprintf('  Bombas en paralelo:   %s  (%d uds.)', o.bomba_modelo{1}, o.n_bombas);
        end
        lines{end+1} = sprintf('  Potencia total:       %.1f HP', o.P_HP);
        lines{end+1} = sprintf('  Punto operación:      Q=%.0f L/min, H=%.1f m', o.Q_oper_Lmin, o.H_oper_m);
        lines{end+1} = sprintf('  Volumen estanque:     %.1f m³', o.V_estanque_m3);
        lines{end+1} = '';
        lines{end+1} = sprintf('  COSTO TOTAL:          $ %s CLP', formato_miles(o.costo_total_CLP));
        lines{end+1} = sprintf('    ├ aspersores:       $ %s', formato_miles(o.costo_aspersores));
        lines{end+1} = sprintf('    ├ tubería:          $ %s', formato_miles(o.costo_tuberia));
        lines{end+1} = sprintf('    └ bomba(s):         $ %s', formato_miles(o.costo_bomba));
        app.handles.textarea_optima.Value = lines;

        app.handles.kpi.config_viables.Text = sprintf('%d', height(V));
        app.handles.kpi.Q_optima.Text       = sprintf('%.0f', o.Q_diseno_Lmin);
        app.handles.kpi.HMT_optima.Text     = sprintf('%.1f', o.HMT_m);
        app.handles.kpi.HP_optima.Text      = sprintf('%.1f', o.P_HP);
        app.handles.kpi.V_estanque.Text     = sprintf('%.1f', o.V_estanque_m3);
        app.handles.kpi.costo_total.Text    = ['$ ' formato_miles(o.costo_total_CLP)];
        app.handles.kpi.n_bombas.Text       = sprintf('%d', o.n_bombas);
        app.handles.kpi.zona_crit.Text      = o.zona_critica{1};

        ax = app.handles.ax_pareto;
        cla(ax);
        scatter(ax, V.P_HP, V.costo_total_CLP/1000, 30, V.V_estanque_m3,'filled', ...
                'MarkerEdgeColor',[0.3 0.3 0.3]);
        hold(ax,'on');
        plot(ax, o.P_HP, o.costo_total_CLP/1000,'rp', ...
             'MarkerSize',20,'MarkerFaceColor','r','LineWidth',1.5);
        hold(ax,'off');
        xlabel(ax,'Potencia bomba [HP]'); ylabel(ax,'Costo total [miles CLP]');
        title(ax, sprintf('%d configuraciones viables', height(V)));
        grid(ax,'on'); grid(ax,'minor');

        app.handles.tg.SelectedTab = app.handles.tab_resultados;
    end

    function analizar_limite_caudal()
        % Calcula, para la óptima ya seleccionada, el caudal MÍNIMO de
        % operación que aún cumple densidad + P_min + cobertura, y el punto
        % (Q, HMT) que resulta → objetivo para elegir la bomba (sin BD_Bombas).
        if isempty(app.resultados) || isempty(app.BD)
            uialert(fig,'Primero ejecute el análisis.','Atención','Icon','warning'); return;
        end
        try
            o = app.resultados.viables(1,:);
            config = config_desde_optima(o);

            % Densidades: usa el modelo de fuego actual si está calculado;
            % si no, las densidades vigentes en parametros.
            if isfield(app.handles,'fuego') && isfield(app.handles.fuego,'resultado')
                casos = leer_caso_fuego();     % un caso (struct) con w0, viento, etc.
            else
                casos = [];                    % la función usa parametros.densidad_*
            end

            % Llamada SIN asignar salida: los callbacks son nested functions
            % (workspace estático) y evalc no puede crear variables nuevas.
            % La función imprime el reporte igual (nargout=0) y evalc lo captura.
            reporte = evalc(['limite_caudal_aspersores(' ...
                             'app.BD, app.parametros, config, casos);']);
            mostrar_ventana_limite(reporte);
            actualizar_estado('Límite de caudal calculado (objetivo de bomba).');
        catch ME
            uialert(fig,['Error en límite de caudal: ' ME.message],'Error','Icon','error');
        end
    end

    function config = config_desde_optima(o)
        config = struct();
        config.asp_techo_id       = id_desde_modelo(app.BD, o.asp_techo{1});
        config.asp_perim_id       = id_desde_modelo(app.BD, o.asp_perim{1});
        config.n_techo            = o.n_techo;
        config.n_perim            = o.n_perim;
        config.DN_principal       = o.DN_princ_mm;
        config.material_principal = o.material_princ{1};
        config.DN_ramal           = o.DN_ramal_mm;
        config.material_ramal     = o.material_ramal{1};
    end

    function id = id_desde_modelo(BD, modelo)
        idx = find(strcmp(string(BD.aspersores.Modelo), string(modelo)), 1);
        if isempty(idx)
            error('No se encontró el aspersor "%s" en la BD de aspersores.', modelo);
        end
        id = BD.aspersores.ID{idx};
    end

    function mostrar_ventana_limite(reporte)
        w = uifigure('Name','Límite de caudal — objetivo de bomba', ...
                     'Position',[140 120 780 640],'Color',[0.96 0.96 0.97]);
        gw = uigridlayout(w,[2 1]); gw.RowHeight = {'1x', 34};
        gw.Padding = [10 10 10 10]; gw.RowSpacing = 6;
        ta = uitextarea(gw,'Editable','off','FontName','Consolas','FontSize',11);
        ta.Layout.Row = 1;
        ta.Value = strsplit(reporte, newline);
        b = uibutton(gw,'Text','Cerrar','ButtonPushedFcn',@(~,~) close(w));
        b.Layout.Row = 2;
    end

    function abrir_graficos()
        if isempty(app.resultados)
            uialert(fig,'Primero ejecute el análisis.','Atención','Icon','warning'); return;
        end
        try
            graficar_resultados(app.resultados, app.parametros, app.iteracion, app.BD);
        catch ME
            uialert(fig,['Error: ' ME.message],'Error','Icon','error');
        end
    end

    function abrir_layout()
        if isempty(app.resultados)
            uialert(fig,'Primero ejecute el análisis.','Atención','Icon','warning'); return;
        end
        try
            graficar_layout(app.resultados.viables(1,:), app.parametros, app.BD);
            graficar_red_hidraulica(app.resultados.viables(1,:), app.parametros);
        catch ME
            uialert(fig,['Error: ' ME.message],'Error','Icon','error');
        end
    end

    function exportar_excel()
        if isempty(app.resultados)
            uialert(fig,'Primero ejecute el análisis.','Atención','Icon','warning'); return;
        end
        try
            writetable(app.resultados.viables,'resultados_viables.xlsx');
            generar_cotizacion(app.resultados.viables(1,:), app.parametros, app.BD, ...
                               'cotizacion_optima.xlsx');
            uialert(fig,['Archivos generados:' newline ...
                         '  • resultados_viables.xlsx (todas las viables)' newline ...
                         '  • cotizacion_optima.xlsx (materiales de la óptima)'], ...
                    'Exportación exitosa','Icon','success');
            actualizar_estado('✓ resultados_viables.xlsx y cotizacion_optima.xlsx exportados');
        catch ME
            uialert(fig,['Error: ' ME.message],'Error','Icon','error');
        end
    end

    function generar_epanet()
        if isempty(app.resultados)
            uialert(fig,'Primero ejecute el análisis.','Atención','Icon','warning'); return;
        end
        try
            [archivo, ruta] = uiputfile({'*.inp','EPANET INP (*.inp)'}, ...
                'Guardar archivo EPANET como...','sistema_incendio.inp');
            if isequal(archivo,0), return; end
            ruta_completa = fullfile(ruta, archivo);

            optima = app.resultados.viables(1,:);
            generar_epanet_inp(optima, app.parametros, app.BD, ruta_completa);

            actualizar_estado(['✓ EPANET generado: ' archivo]);
            uialert(fig,sprintf(['Archivo EPANET generado:\n%s\n\n' ...
                'Asegúrese de que "plano_vivienda.bmp" esté en la misma carpeta ' ...
                'para que el fondo aparezca al abrir el .inp en EPANET.'], ruta_completa), ...
                'EPANET generado','Icon','success');
        catch ME
            uialert(fig,['Error generando EPANET: ' ME.message],'Error','Icon','error');
        end
    end

    function guardar_config()
        [archivo, ruta] = uiputfile({'*.mat','Configuración MATLAB (*.mat)'}, ...
            'Guardar configuración como...','config_sistema.mat');
        if isequal(archivo,0), return; end

        try
            parametros = app.parametros;
            iteracion  = app.iteracion;
            escenarios = app.escenarios;
            save(fullfile(ruta,archivo), 'parametros','iteracion','escenarios');
            actualizar_estado(['✓ Configuración guardada: ' archivo]);
            uialert(fig,'Configuración guardada correctamente.','Guardado','Icon','success');
        catch ME
            uialert(fig,['Error: ' ME.message],'Error','Icon','error');
        end
    end

    function cargar_config()
        [archivo, ruta] = uigetfile({'*.mat','Configuración MATLAB (*.mat)'}, ...
            'Cargar configuración...');
        if isequal(archivo,0), return; end

        try
            S = load(fullfile(ruta,archivo));
            if isfield(S,'parametros'), app.parametros = migrar_parametros(S.parametros); end
            if isfield(S,'iteracion'),  app.iteracion  = S.iteracion;  end
            if isfield(S,'escenarios'), app.escenarios = S.escenarios; end

            actualizar_widgets_desde_app();
            actualizar_tabla_comparador();
            actualizar_estado(['✓ Configuración cargada: ' archivo]);
            uialert(fig,'Configuración cargada. Los widgets fueron actualizados.', ...
                    'Cargado','Icon','success');
        catch ME
            uialert(fig,['Error: ' ME.message],'Error','Icon','error');
        end
    end

    function actualizar_widgets_desde_app()
        % Sincroniza todos los widgets con los valores actuales en app.parametros / app.iteracion
        campos_param = {'area_techo_m2','perimetro_m','ancho_franja_m','n_ventanas', ...
            'L_aduccion_m','L_montante_techo_m', ...
            'L_ramal_perim_unit_m','L_ramal_vent_m','densidad_techo_Lmin_m2', ...
            'densidad_perimetro_Lmin_m2','t_operacion_min','factor_seg_caudal', ...
            'factor_seg_volumen','factor_localizadas','v_max_principal', ...
            'v_max_ramal','costo_kWh_CLP','factor_arranque', ...
            'n_bombas_paralelo_max','HP_max_paralelo'};
        for i = 1:numel(campos_param)
            f = campos_param{i};
            if isfield(app.handles, ['sl_' f]) && isfield(app.parametros, f)
                v = app.parametros.(f);
                app.handles.(['sl_' f]).Value = v;
                app.handles.(['ed_' f]).Value = v;
            end
        end

        campos_iter = {'n_techo_min','n_techo_max','n_perimetro_min','n_perimetro_max'};
        for i = 1:numel(campos_iter)
            f = campos_iter{i};
            if isfield(app.handles, ['sl_' f]) && isfield(app.iteracion, f)
                v = app.iteracion.(f);
                app.handles.(['sl_' f]).Value = v;
                app.handles.(['ed_' f]).Value = v;
            end
        end

        % Modo activacion
        if strcmp(app.parametros.modo_activacion, 'simultaneo')
            app.handles.rb_sim.Value = true;
        else
            app.handles.rb_zon.Value = true;
        end

        % Nebulizadores de ventana (checkbox) y H estática derivada
        if isfield(app.handles,'cb_neb')
            app.handles.cb_neb.Value = logical(app.parametros.usar_nebulizadores);
        end
        if isfield(app.handles,'lbl_alto')
            app.handles.lbl_alto.Text = sprintf('%.1f', ...
                app.parametros.L_montante_techo_m - app.parametros.z_agua_estanque_m);
        end

        % Criterio optimo
        app.handles.dd_criterio.Value = app.iteracion.criterio_optimo;

        % --- Disposición geométrica ---
        if isfield(app.parametros, 'disp')
            campos_disp = {'largo_m','ancho_m','saliente_x_m','saliente_ancho_m', ...
                           'saliente_largo_m','sep_aspersores_m','sep_perimetro_m'};
            for i = 1:numel(campos_disp)
                f = campos_disp{i};
                if isfield(app.handles, ['sl_' f]) && isfield(app.parametros.disp, f)
                    v = app.parametros.disp.(f);
                    app.handles.(['sl_' f]).Value = max(app.handles.(['sl_' f]).Limits(1), ...
                        min(app.handles.(['sl_' f]).Limits(2), v));
                    app.handles.(['ed_' f]).Value = v;
                end
            end
            if isfield(app.handles,'dd_forma'),  app.handles.dd_forma.Value  = app.parametros.disp.forma; end
            if isfield(app.handles,'dd_techo'),  app.handles.dd_techo.Value  = app.parametros.disp.tipo_techo; end
            if isfield(app.handles,'dd_orient'), app.handles.dd_orient.Value = app.parametros.disp.orientacion_cumbrera; end
            refrescar_geometria();
        end
    end

    function reset_defaults()
        sel = uiconfirm(fig,'¿Restablecer todos los parámetros a valores por defecto?', ...
                        'Confirmar reset','Options',{'Sí, resetear','Cancelar'}, ...
                        'DefaultOption',2,'CancelOption',2);
        if strcmp(sel,'Sí, resetear')
            app.parametros = parametros_default();
            app.iteracion  = iteracion_default();
            actualizar_widgets_desde_app();
            actualizar_estado('Parámetros restablecidos a defaults.');
        end
    end

    function p = migrar_parametros(p)
        % Completa configuraciones antiguas (.mat) con los campos del modelo
        % de trazado real (aducción + anillo + montantes/ramales por aspersor).
        if ~isfield(p,'L_aduccion_m') && isfield(p,'L_principal_m')
            p.L_aduccion_m = p.L_principal_m;   % equivalencia aproximada
        end
        def = parametros_default();
        campos = fieldnames(def);
        for ii = 1:numel(campos)
            if ~isfield(p, campos{ii})
                p.(campos{ii}) = def.(campos{ii});
            end
        end
    end

    function actualizar_estado(texto)
        if isfield(app.handles,'lbl_estado') && isvalid(app.handles.lbl_estado)
            app.handles.lbl_estado.Text = texto;
            drawnow;
        end
    end

    function s = formato_miles(n)
        if isnan(n), s = '—'; return; end
        s = regexprep(num2str(round(n)), '\d{1,3}(?=(\d{3})+$)', '$0.');
    end

end
