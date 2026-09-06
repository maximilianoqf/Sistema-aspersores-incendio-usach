function graficar_layout(optima, parametros, BD)
%GRAFICAR_LAYOUT  Dibuja la planta de la vivienda con la disposición de
%   aspersores de la configuración óptima y sus círculos de cobertura.
%
%   graficar_layout(optima, parametros, BD)
%
%   La geometría se obtiene del motor paramétrico geometria_vivienda, a
%   partir de parametros.disp (forma, largo, ancho, tipo de techo, etc.).
%   Si parametros no trae el campo .disp, se usa una vivienda rectangular
%   por defecto cuyas dimensiones se estiman desde area_techo_m2 y
%   perimetro_m para mantener la coherencia con el cálculo hidráulico.
%
%   Genera una figura con:
%       • Contorno de la vivienda (a escala, según las dimensiones dadas)
%       • Ventanas marcadas con líneas azules
%       • Aspersores de TECHO sobre las cumbreras
%       • Aspersores de PERÍMETRO en la franja de defensa
%       • NEBULIZADORES, uno por ventana
%       • Círculos de cobertura semitransparentes por tipo
%       • Franja de defensa marcada

    if nargin < 3 || isempty(BD)
        error('graficar_layout requiere la estructura BD.');
    end

    % --- Asegurar disposición paramétrica ---
    parametros = geometria_vivienda('asegurar', parametros);

    % =========================================================
    % 1. Geometría desde el motor paramétrico
    % =========================================================
    geo = geometria_vivienda('construir', parametros);

    % =========================================================
    % 2. Radios de los aspersores (de la BD)
    % =========================================================
    radio_techo = BD.aspersores.Radio_m( ...
        strcmp(BD.aspersores.Modelo, optima.asp_techo{1}));
    radio_perim = BD.aspersores.Radio_m( ...
        strcmp(BD.aspersores.Modelo, optima.asp_perim{1}));

    % La zona de ventanas es opcional (usar_nebulizadores = false → n_vent = 0)
    usar_vent = optima.n_vent > 0;
    if usar_vent
        radio_vent = BD.aspersores.Radio_m( ...
            strcmp(BD.aspersores.Modelo, optima.asp_vent{1}));
    else
        radio_vent = 0;
    end

    if isempty(radio_techo) || isempty(radio_perim) || (usar_vent && isempty(radio_vent))
        error('No se encontró algún modelo de aspersor en la BD.');
    end

    % =========================================================
    % 3. Distribución de aspersores (vía motor)
    %    Trazado real: los aspersores de techo van sobre MONTANTES que suben
    %    desde el anillo perimetral (contorno de la vivienda).
    % =========================================================
    pos_techo = geometria_vivienda('distribuir_perimetro', geo, optima.n_techo, 0);
    pos_perim = geometria_vivienda('distribuir_perimetro', geo, optima.n_perim, ...
                                   parametros.ancho_franja_m);
    if usar_vent
        pos_vent = geo.ventanas_centros;
    else
        pos_vent = zeros(0,2);
    end

    % =========================================================
    % 4. Figura
    % =========================================================
    fig = figure('Name','Layout — Disposición de aspersores', ...
                 'Position',[50 50 1200 950], 'Color','w');
    hold on; axis equal;

    % Franja de defensa
    franja = geometria_vivienda('expandir', geo.contorno, parametros.ancho_franja_m);
    fill(franja(:,1), franja(:,2), [0.95 0.92 0.80], ...
         'EdgeColor',[0.7 0.6 0.4],'LineStyle',':','LineWidth',1.2, ...
         'FaceAlpha',0.5, 'DisplayName', ...
         sprintf('Franja de defensa (%.1f m)', parametros.ancho_franja_m));

    % Coberturas
    for i = 1:size(pos_perim,1)
        dibujar_circulo(pos_perim(i,1), pos_perim(i,2), radio_perim, [0.40 0.60 0.85], 0.15);
    end
    for i = 1:size(pos_techo,1)
        dibujar_circulo(pos_techo(i,1), pos_techo(i,2), radio_techo, [0.95 0.65 0.30], 0.20);
    end
    for i = 1:size(pos_vent,1)
        dibujar_circulo(pos_vent(i,1), pos_vent(i,2), radio_vent, [0.30 0.75 0.55], 0.25);
    end

    % Contorno
    fill(geo.contorno(:,1), geo.contorno(:,2), [0.98 0.98 0.98], ...
         'EdgeColor','k', 'LineWidth',2.5, 'HandleVisibility','off');

    % Tabiques (si los hubiera)
    for k = 1:numel(geo.tabiques)
        T = geo.tabiques{k};
        plot(T(:,1), T(:,2), 'Color',[0.3 0.3 0.3], 'LineWidth',1.2, ...
             'HandleVisibility','off');
    end

    % Ventanas
    for k = 1:numel(geo.ventanas)
        V = geo.ventanas{k};
        plot(V(:,1), V(:,2), '-', 'Color',[0.20 0.45 0.75], 'LineWidth',3, ...
             'HandleVisibility','off');
    end

    % Etiquetas de ambientes
    for k = 1:numel(geo.etiquetas)
        E = geo.etiquetas{k};
        text(E.x, E.y, E.nombre, 'HorizontalAlignment','center', ...
             'FontWeight','bold', 'FontSize',10, 'Color',[0.3 0.3 0.3]);
    end

    % Cumbreras (guías)
    for k = 1:numel(geo.cumbreras)
        C = geo.cumbreras{k};
        plot(C(:,1), C(:,2), '--', 'Color',[0.6 0.3 0.1], 'LineWidth',1.0, ...
             'HandleVisibility','off');
    end

    % Marcadores de aspersores
    h_t = plot(pos_techo(:,1), pos_techo(:,2), 'o', ...
               'MarkerFaceColor',[0.95 0.45 0.10], 'MarkerEdgeColor','k', ...
               'MarkerSize',9, 'LineWidth',1.2);
    h_p = plot(pos_perim(:,1), pos_perim(:,2), 's', ...
               'MarkerFaceColor',[0.20 0.45 0.75], 'MarkerEdgeColor','k', ...
               'MarkerSize',9, 'LineWidth',1.2);
    if usar_vent
        h_v = plot(pos_vent(:,1), pos_vent(:,2), '^', ...
                   'MarkerFaceColor',[0.30 0.75 0.55], 'MarkerEdgeColor','k', ...
                   'MarkerSize',11, 'LineWidth',1.2);
    end

    % Estilo de ejes
    grid on; grid minor;
    xlabel('X [m]', 'FontSize',11);
    ylabel('Y [m]', 'FontSize',11);

    xmin = min(franja(:,1)) - 1;  xmax = max(franja(:,1)) + 1;
    ymin = min(franja(:,2)) - 1;  ymax = max(franja(:,2)) + 1;
    xlim([xmin xmax]); ylim([ymin ymax]);

    % Separación media real entre aspersores de techo (informativo)
    sep_real = separacion_media(pos_techo);

    titulo = sprintf(['Layout óptimo | %s %.1f×%.1f m | %d techo (%s, R=%.1fm) + ' ...
                      '%d perim (%s, R=%.1fm)'], ...
                     upper(parametros.disp.forma), parametros.disp.largo_m, ...
                     parametros.disp.ancho_m, ...
                     optima.n_techo, optima.asp_techo{1}, radio_techo, ...
                     optima.n_perim, optima.asp_perim{1}, radio_perim);
    if usar_vent
        titulo = sprintf('%s + %d vent (%s, R=%.1fm)', titulo, ...
                         optima.n_vent, optima.asp_vent{1}, radio_vent);
    else
        titulo = [titulo ' | sin nebulizadores'];
    end
    title(titulo, 'FontSize',11, 'FontWeight','bold');

    handles_leg  = [h_t h_p];
    textos_leg = {sprintf('Techo: %d × %s (sep≈%.1f m)', optima.n_techo, optima.asp_techo{1}, sep_real), ...
                  sprintf('Perímetro: %d × %s', optima.n_perim, optima.asp_perim{1})};
    if usar_vent
        handles_leg(end+1) = h_v;
        textos_leg{end+1}  = sprintf('Ventanas: %d × %s', optima.n_vent, optima.asp_vent{1});
    end
    legend(handles_leg, textos_leg, 'Location','northeastoutside', 'FontSize',9);

    % Guardar PNG
    try
        exportgraphics(fig, 'fig3_layout_aspersores.png', 'Resolution',150);
        fprintf('  ✓ Layout exportado a fig3_layout_aspersores.png\n');
    catch
        warning('No se pudo exportar el layout.');
    end
end


% =====================================================================
%  AUXILIARES LOCALES (solo dibujo / compatibilidad)
% =====================================================================
function s = separacion_media(pos)
    if size(pos,1) < 2, s = 0; return; end
    d = diff(pos);
    s = mean(sqrt(sum(d.^2, 2)));
end


function dibujar_circulo(cx, cy, r, color, alpha)
%DIBUJAR_CIRCULO  Disco semitransparente.
    theta = linspace(0, 2*pi, 60);
    x = cx + r*cos(theta);
    y = cy + r*sin(theta);
    fill(x, y, color, 'EdgeColor',color*0.7, 'FaceAlpha',alpha, ...
         'LineWidth',0.8, 'HandleVisibility','off');
end
