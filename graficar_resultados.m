function graficar_resultados(resultados, parametros, iteracion, BD)
%GRAFICAR_RESULTADOS  Genera los gráficos comparativos del análisis.
%
%   graficar_resultados(resultados, parametros, iteracion, BD)
%
%   BD es opcional: si se entrega, el subplot de "curva sistema vs bomba"
%   dibuja la curva REAL de la bomba óptima (interpolada).
%
%   Crea 2 figuras:
%       Figura 1: Visión global (Pareto + distribuciones + top-10)
%       Figura 2: Configuración óptima en detalle (curvas + componentes + costos)

    if nargin < 4
        BD = [];
    end

    if isempty(resultados.viables)
        warning('No hay configuraciones viables para graficar.');
        return;
    end

    V = resultados.viables;
    optima = V(1, :);

    % =====================================================================
    % FIGURA 1 — VISIÓN GLOBAL
    % =====================================================================
    fig1 = figure('Name','Análisis paramétrico — Visión global', ...
                  'Position',[50 80 1300 800], 'Color','w');

    % ---- Subplot 1: Pareto Costo vs Potencia ----
    subplot(2,2,1);
    scatter(V.P_HP, V.costo_total_CLP/1000, 35, V.V_estanque_m3, 'filled', ...
            'MarkerEdgeColor',[0.3 0.3 0.3]); hold on;
    plot(optima.P_HP, optima.costo_total_CLP/1000, 'rp', ...
         'MarkerSize',22, 'MarkerFaceColor','r', 'LineWidth',1.5);
    cb = colorbar; ylabel(cb, 'V_{estanque} [m³]');
    xlabel('Potencia bomba [HP]');
    ylabel('Costo total [miles CLP]');
    title('Pareto: Costo vs Potencia (color = volumen)');
    grid on; grid minor;
    legend({'Configuraciones viables','Óptima'}, 'Location','best');

    % ---- Subplot 2: Distribución de potencias ----
    subplot(2,2,2);
    pots_unicas = unique(V.P_HP);
    counts = arrayfun(@(p) sum(V.P_HP == p), pots_unicas);
    bar(pots_unicas, counts, 'FaceColor',[0.40 0.60 0.85]);
    xlabel('Potencia [HP]');
    ylabel('N° configuraciones');
    title('Distribución de potencia de bomba');
    grid on;
    for k = 1:numel(pots_unicas)
        text(pots_unicas(k), counts(k) + max(counts)*0.02, sprintf('%d',counts(k)), ...
             'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
    end

    % ---- Subplot 3: Caudal vs HMT ----
    subplot(2,2,3);
    scatter(V.Q_diseno_Lmin, V.HMT_m, 35, V.costo_total_CLP/1000, 'filled', ...
            'MarkerEdgeColor',[0.3 0.3 0.3]); hold on;
    plot(optima.Q_diseno_Lmin, optima.HMT_m, 'rp', ...
         'MarkerSize',22, 'MarkerFaceColor','r', 'LineWidth',1.5);
    cb = colorbar; ylabel(cb, 'Costo [miles CLP]');
    xlabel('Caudal de diseño [L/min]');
    ylabel('HMT [m.c.a.]');
    title('Curvas de operación requeridas');
    grid on; grid minor;

    % ---- Subplot 4: Top-10 por score ----
    subplot(2,2,4);
    n_top = min(10, height(V));
    top = V(1:n_top, :);
    barh(1:n_top, top.score, 'FaceColor',[0.85 0.40 0.30]);
    set(gca,'YDir','reverse');
    yticks(1:n_top);
    etiquetas = arrayfun(@(i) sprintf('#%d %dT/%dP %.1fHP', ...
                                      top.config_id(i), top.n_techo(i), ...
                                      top.n_perim(i), top.P_HP(i)), ...
                         1:n_top, 'UniformOutput', false);
    yticklabels(etiquetas);
    xlabel(sprintf('Score (%s)', iteracion.criterio_optimo));
    title(sprintf('Top-%d configuraciones', n_top));
    grid on;

    sgtitle('Análisis paramétrico — sistema contra incendios forestales', ...
            'FontSize',14, 'FontWeight','bold');

    % =====================================================================
    % FIGURA 2 — CONFIGURACIÓN ÓPTIMA EN DETALLE
    % =====================================================================
    fig2 = figure('Name','Configuración óptima — detalle', ...
                  'Position',[100 100 1300 800], 'Color','w');

    % ---- Subplot 1: Curva sistema vs curva bomba ----
    subplot(2,2,1); hold on;

    % Curva del sistema: H_sys(Q) = H_estática + H_aspersor + k·Q^1.852
    % La estática es la de la zona crítica (viene en la fila de resultados;
    % fallback a los parámetros para resultados de versiones antiguas).
    if ismember('H_estatica_m', V.Properties.VariableNames) && ~isnan(optima.H_estatica_m)
        H_estatica = optima.H_estatica_m;
    elseif isfield(parametros, 'H_estatica_m')
        H_estatica = parametros.H_estatica_m;
    else
        H_estatica = 2.1;   % montante de techo por defecto
    end
    H_aspersor  = optima.H_aspersor_m;
    h_perdidas  = optima.h_friccion_m + optima.h_localizada_m;
    k_sys       = h_perdidas / optima.Q_diseno_Lmin^1.852;

    Q_range = linspace(0.1, 1.4 * optima.Q_diseno_Lmin, 300);
    H_sys   = H_estatica + H_aspersor + k_sys .* Q_range.^1.852;

    plot(Q_range, H_sys, '-', 'Color',[0.85 0.40 0.30], 'LineWidth',2.5, ...
         'DisplayName','Curva sistema');

    % Curva de la bomba (si BD disponible) — combinada si N>1 en paralelo
    if ~isempty(BD)
        idx_bomba = find(strcmp(BD.bombas.Modelo, optima.bomba_modelo{1}), 1);
        if ~isempty(idx_bomba)
            Q_b = BD.bombas.Q_curva{idx_bomba};
            H_b = BD.bombas.H_curva{idx_bomba};

            % Si hay N bombas en paralelo, el caudal a igual H se multiplica
            N_par = 1;
            if ismember('n_bombas', V.Properties.VariableNames) && ...
               ~isnan(optima.n_bombas)
                N_par = optima.n_bombas;
            end
            Q_b_eff = Q_b * N_par;

            Q_b_fino = linspace(min(Q_b_eff), max(Q_b_eff), 200);
            H_b_fino = interp1(Q_b_eff, H_b, Q_b_fino, 'pchip');

            if N_par > 1
                etiqueta = sprintf('%d × %s (paralelo)', N_par, optima.bomba_modelo{1});
            else
                etiqueta = sprintf('Bomba %s', optima.bomba_modelo{1});
            end

            plot(Q_b_fino, H_b_fino, '-', 'Color',[0.20 0.45 0.75], ...
                 'LineWidth',2.5, 'DisplayName',etiqueta);
            plot(Q_b_eff, H_b, 'o', 'Color',[0.20 0.45 0.75], ...
                 'MarkerFaceColor',[0.20 0.45 0.75], 'HandleVisibility','off');
        end
    end

    % Punto de operación real
    plot(optima.Q_oper_Lmin, optima.H_oper_m, 'p', ...
         'MarkerSize',18, 'MarkerFaceColor','y', 'MarkerEdgeColor','k', ...
         'LineWidth',1.5, 'DisplayName','Punto operación');

    yline(optima.HMT_m, '--', sprintf('HMT_{req} = %.1f m', optima.HMT_m), ...
          'Color',[0.5 0.5 0.5], 'HandleVisibility','off');
    xline(optima.Q_diseno_Lmin, '--', sprintf('Q_{diseño} = %.0f L/min', optima.Q_diseno_Lmin), ...
          'Color',[0.5 0.5 0.5], 'HandleVisibility','off');

    xlabel('Caudal Q [L/min]');
    ylabel('Altura H [m.c.a.]');
    title('Punto de operación bomba-sistema');
    legend('Location','best');
    grid on; grid minor;

    % ---- Subplot 2: Componentes de la HMT ----
    subplot(2,2,2);
    componentes = [H_estatica, ...
                   optima.h_friccion_m, ...
                   optima.h_localizada_m, ...
                   optima.H_aspersor_m];
    etiquetas_comp = {'Estática','Fricción','Localizadas','Aspersor'};
    colores = [0.55 0.55 0.55; 0.85 0.40 0.30; 0.95 0.65 0.30; 0.20 0.45 0.75];

    b = bar(componentes, 'FaceColor','flat');
    for k = 1:numel(componentes)
        b.CData(k,:) = colores(k,:);
        text(k, componentes(k) + max(componentes)*0.02, ...
             sprintf('%.1f m\n(%.0f%%)', componentes(k), ...
                     100*componentes(k)/sum(componentes)), ...
             'HorizontalAlignment','center', 'FontSize',9, 'FontWeight','bold');
    end
    xticklabels(etiquetas_comp);
    ylabel('Altura [m.c.a.]');
    title(sprintf('Componentes HMT (total: %.1f m)', optima.HMT_m));
    grid on;

    % ---- Subplot 3: Caudales por zona ----
    subplot(2,2,3);
    Q_zonas = [optima.Q_techo_Lmin, optima.Q_perim_Lmin, optima.Q_vent_Lmin];
    nombres_zona = {'Techo','Perímetro','Ventanas'};
    colores_z = [0.95 0.65 0.30; 0.40 0.60 0.85; 0.30 0.75 0.55];

    b3 = bar(Q_zonas, 'FaceColor','flat');
    for k = 1:numel(Q_zonas)
        b3.CData(k,:) = colores_z(k,:);
        text(k, Q_zonas(k) + max(Q_zonas)*0.02, sprintf('%.0f L/min', Q_zonas(k)), ...
             'HorizontalAlignment','center','FontSize',10,'FontWeight','bold');
    end
    xticklabels(nombres_zona);
    ylabel('Caudal por zona [L/min]');
    title(sprintf('Caudal por zona (crítica: %s)', optima.zona_critica{1}));
    grid on;

    % Línea horizontal con caudal de diseño
    yline(optima.Q_diseno_Lmin, '--r', ...
          sprintf('Q_{diseño} = %.0f L/min', optima.Q_diseno_Lmin), ...
          'LineWidth',1.5);

    % ---- Subplot 4: Distribución del costo (datos reales) ----
    subplot(2,2,4);
    costos = [optima.costo_aspersores, optima.costo_tuberia, optima.costo_bomba];
    etiquetas_costo = { ...
        sprintf('Aspersores\n$%s', formato_miles(optima.costo_aspersores)), ...
        sprintf('Tubería\n$%s',    formato_miles(optima.costo_tuberia)), ...
        sprintf('Bomba\n$%s',      formato_miles(optima.costo_bomba)) };
    pie(costos, etiquetas_costo);
    title(sprintf('Distribución costo (total $%s)', formato_miles(optima.costo_total_CLP)));
    colormap(gca, [0.20 0.45 0.75; 0.95 0.65 0.30; 0.85 0.40 0.30]);

    sgtitle(sprintf('Configuración óptima — %d Techo + %d Perim + %d Vent | %s | %.1f HP', ...
                    optima.n_techo, optima.n_perim, optima.n_vent, ...
                    optima.bomba_modelo{1}, optima.P_HP), ...
            'FontSize',13, 'FontWeight','bold');

    % --- Guardar figuras como PNG ---
    try
        exportgraphics(fig1, 'fig1_vision_global.png',  'Resolution',150);
        exportgraphics(fig2, 'fig2_optima_detalle.png', 'Resolution',150);
        fprintf('  ✓ Gráficos exportados a PNG\n');
    catch
        warning('No se pudieron exportar las figuras automáticamente.');
    end
end


function s = formato_miles(n)
    s = regexprep(num2str(round(n)), '\d{1,3}(?=(\d{3})+$)', '$0.');
end
