function graficar_red_hidraulica(optima, parametros)
%GRAFICAR_RED_HIDRAULICA  Plano esquemático de la red hidráulica.
%
%   graficar_red_hidraulica(optima, parametros)
%
%   Dibuja el trazado real del sistema en dos vistas:
%       • PLANTA:    estanque + bomba → aducción → anillo perimetral
%                    (DN principal) alrededor de la vivienda, con los
%                    montantes de techo (magenta) y los ramales
%                    perimetrales (azul) derivados del anillo.
%       • ELEVACIÓN: vista lateral con el anillo a nivel de terreno, los
%                    montantes subiendo L_montante, los aspersores
%                    perimetrales a nivel de piso y el estanque/bomba.
%
%   'optima' es una fila de resultados.viables (usa n_techo, n_perim,
%   n_vent y los DN). La geometría sale de geometria_vivienda, así el
%   plano es consistente con el layout y el cálculo hidráulico.
%
%   Exporta la figura a fig4_red_hidraulica.png.

    % --- Colores (mismo código que los planos CAD del proyecto) ---
    c_princ = [0.85 0.20 0.20];   % rojo   → principal (anillo + aducción)
    c_perim = [0.20 0.35 0.85];   % azul   → ramales perimetrales
    c_mont  = [0.85 0.25 0.65];   % magenta→ montantes de techo
    c_asp_t = [0.95 0.55 0.10];   % naranjo→ boquilla de techo
    c_vent  = [0.30 0.75 0.55];   % verde  → nebulizadores
    c_casa  = [0.45 0.45 0.45];

    % =========================================================
    % 1. Geometría y parámetros del trazado
    % =========================================================
    parametros = geometria_vivienda('asegurar', parametros);
    geo = geometria_vivienda('construir', parametros);

    L_adu  = obtener(parametros, 'L_aduccion_m', 5);
    L_mont = obtener(parametros, 'L_montante_techo_m', 2.1);
    L_rper = obtener(parametros, 'L_ramal_perim_unit_m', 2.5);
    z_vent = obtener(parametros, 'z_aspersor_vent_m', 1.5);
    alto_casa = obtener(parametros, 'alto_vivienda_m', max(2.4, L_mont + 0.3));

    n_t = optima.n_techo;
    n_p = optima.n_perim;
    usar_vent = optima.n_vent > 0;

    contorno = geo.contorno;
    xmin = min(contorno(:,1));  xmax = max(contorno(:,1));
    ymin = min(contorno(:,2));  ymax = max(contorno(:,2));
    ymid = (ymin + ymax)/2;

    % Estaciones sobre el anillo (montantes) y ramales perimetrales
    pos_mont = geometria_vivienda('distribuir_perimetro', geo, n_t, 0);
    base_per = geometria_vivienda('distribuir_perimetro', geo, n_p, 0);
    tip_per  = zeros(n_p, 2);
    for i = 1:n_p
        nrm = normal_exterior(contorno, base_per(i,:));
        tip_per(i,:) = base_per(i,:) + L_rper * nrm;
    end

    % Punto de alimentación del anillo (lado del estanque, al oriente)
    p_feed = punto_mas_cercano(contorno, [xmax, ymid]);
    x_est  = p_feed(1) + L_adu;          % borde izquierdo del estanque
    w_est  = 1.2;  h_est = 1.2;          % estanque esquemático

    fig = figure('Name','Red hidráulica — planta y elevación', ...
                 'Position',[60 60 1450 640], 'Color','w');

    % =========================================================
    % 2. VISTA EN PLANTA
    % =========================================================
    subplot(1,2,1); hold on; axis equal;

    % Casa (contorno de referencia)
    fill(contorno(:,1), contorno(:,2), [0.97 0.97 0.97], ...
         'EdgeColor',c_casa, 'LineStyle','--', 'LineWidth',1.0, ...
         'HandleVisibility','off');
    text(mean(contorno(1:end-1,1)), mean(contorno(1:end-1,2)), 'VIVIENDA', ...
         'HorizontalAlignment','center', 'Color',c_casa, ...
         'FontWeight','bold', 'FontSize',10);

    % Anillo principal (sigue el contorno) + aducción al estanque
    h_anillo = plot(contorno(:,1), contorno(:,2), '-', ...
                    'Color',c_princ, 'LineWidth',2.5);
    plot([p_feed(1) x_est], [p_feed(2) p_feed(2)], '-', ...
         'Color',c_princ, 'LineWidth',2.5, 'HandleVisibility','off');

    % Estanque y bomba
    rectangle('Position',[x_est, p_feed(2)-h_est/2, w_est, h_est], ...
              'EdgeColor','k', 'LineWidth',1.2, 'FaceColor',[0.94 0.94 0.98]);
    text(x_est + w_est/2, p_feed(2) + h_est/2 + 0.5, 'Estanque', ...
         'HorizontalAlignment','center', 'FontSize',9);
    h_bomba = plot(p_feed(1) + 0.75*L_adu, p_feed(2), 'ks', ...
                   'MarkerFaceColor',[0.3 0.3 0.3], 'MarkerSize',9);

    % Ramales perimetrales (azul) con su aspersor al final
    for i = 1:n_p
        plot([base_per(i,1) tip_per(i,1)], [base_per(i,2) tip_per(i,2)], ...
             '-', 'Color',c_perim, 'LineWidth',1.8, 'HandleVisibility','off');
    end
    h_perim = plot(tip_per(:,1), tip_per(:,2), 'o', ...
                   'MarkerFaceColor',c_perim, 'MarkerEdgeColor','k', 'MarkerSize',7);

    % Montantes de techo (magenta): en planta se ven como puntos en el anillo
    h_mont = plot(pos_mont(:,1), pos_mont(:,2), 's', ...
                  'MarkerFaceColor',c_mont, 'MarkerEdgeColor','k', 'MarkerSize',9);

    % Nebulizadores de ventana (opcionales)
    if usar_vent
        pv = geo.ventanas_centros;
        h_vent = plot(pv(:,1), pv(:,2), '^', ...
                      'MarkerFaceColor',c_vent, 'MarkerEdgeColor','k', 'MarkerSize',8);
    end

    grid on;
    xlabel('X [m]'); ylabel('Y [m]');
    title(sprintf('PLANTA — anillo DN%d + aducción %.1f m | ramales DN%d', ...
          optima.DN_princ_mm, L_adu, optima.DN_ramal_mm), 'FontSize',10);

    handles_leg = [h_anillo h_mont h_perim h_bomba];
    textos_leg = {sprintf('Principal DN%d (anillo + aducción)', optima.DN_princ_mm), ...
                  sprintf('Montante techo DN%d (%d ud., sube %.1f m)', optima.DN_ramal_mm, n_t, L_mont), ...
                  sprintf('Ramal perímetro DN%d (%d ud., %.1f m c/u)', optima.DN_ramal_mm, n_p, L_rper), ...
                  'Bomba'};
    if usar_vent
        handles_leg(end+1) = h_vent;
        textos_leg{end+1}  = sprintf('Nebulizador ventana (%d ud.)', optima.n_vent);
    end
    legend(handles_leg, textos_leg, 'Location','southoutside', 'FontSize',8);

    % =========================================================
    % 3. VISTA EN ELEVACIÓN (mirando el eje Y; alturas reales)
    % =========================================================
    subplot(1,2,2); hold on;

    x_est2 = xmax + L_adu;               % estanque a L_adu del borde oriente

    % Terreno
    plot([xmin - L_rper - 1, x_est2 + w_est + 1], [0 0], '-', ...
         'Color',[0.35 0.25 0.15], 'LineWidth',1.5, 'HandleVisibility','off');

    % Casa (silueta)
    fill([xmin xmax xmax xmin], [0 0 alto_casa alto_casa], [0.97 0.97 0.97], ...
         'EdgeColor',c_casa, 'LineStyle','--', 'LineWidth',1.0, ...
         'HandleVisibility','off');
    text((xmin+xmax)/2, alto_casa/2, 'VIVIENDA', 'HorizontalAlignment','center', ...
         'Color',c_casa, 'FontWeight','bold', 'FontSize',10);

    % Anillo a nivel de terreno (en elevación se proyecta como una línea)
    plot([xmin xmax], [0 0], '-', 'Color',c_princ, 'LineWidth',3, ...
         'HandleVisibility','off');
    % Aducción hasta el estanque
    plot([xmax x_est2], [0 0], '-', 'Color',c_princ, 'LineWidth',2.5, ...
         'HandleVisibility','off');

    % Montantes de techo: suben L_mont desde el anillo, boquilla en la punta
    for i = 1:n_t
        xm = pos_mont(i,1);
        plot([xm xm], [0 L_mont], '-', 'Color',c_mont, 'LineWidth',2, ...
             'HandleVisibility','off');
    end
    h_asp_t = plot(pos_mont(:,1), L_mont*ones(n_t,1), 'o', ...
                   'MarkerFaceColor',c_asp_t, 'MarkerEdgeColor','k', 'MarkerSize',8);

    % Aspersores perimetrales: a nivel de terreno (proyectados)
    h_asp_p = plot(tip_per(:,1), zeros(n_p,1), 'o', ...
                   'MarkerFaceColor',c_perim, 'MarkerEdgeColor','k', 'MarkerSize',7);

    % Nebulizadores de ventana a su altura (proyectados sobre la fachada)
    if usar_vent
        pv = geo.ventanas_centros;
        h_vent2 = plot(pv(:,1), z_vent*ones(size(pv,1),1), '^', ...
                       'MarkerFaceColor',c_vent, 'MarkerEdgeColor','k', 'MarkerSize',8);
    end

    % Estanque y bomba
    rectangle('Position',[x_est2, 0, w_est, h_est], ...
              'EdgeColor','k', 'LineWidth',1.2, 'FaceColor',[0.94 0.94 0.98]);
    text(x_est2 + w_est/2, h_est + 0.4, 'Estanque', ...
         'HorizontalAlignment','center', 'FontSize',9);
    plot(xmax + 0.75*L_adu, 0.15, 'ks', 'MarkerFaceColor',[0.3 0.3 0.3], ...
         'MarkerSize',9, 'HandleVisibility','off');
    text(xmax + 0.75*L_adu, 0.65, 'Bomba', 'HorizontalAlignment','center', ...
         'FontSize',8);

    % Cota del montante (sobre el montante más a la izquierda)
    if n_t > 0
        [~, i_izq] = min(pos_mont(:,1));
        xm = pos_mont(i_izq,1);
        text(xm, L_mont + 0.35, sprintf('+%.1f m', L_mont), ...
             'HorizontalAlignment','center', 'FontSize',8, 'Color',c_mont);
    end

    grid on;
    % Escala real en ambos ejes con límites explícitos (daspect respeta
    % los límites, a diferencia de axis equal que recorta el eje X).
    daspect([1 1 1]);
    xlim([xmin - L_rper - 1.5, x_est2 + w_est + 1]);
    ylim([-1.2, max(alto_casa, L_mont) + 1.5]);
    xlabel('X [m]'); ylabel('Z [m]');
    title('ELEVACIÓN (esquemática) — anillo a nivel de terreno', 'FontSize',10);

    handles_leg2 = h_asp_t;
    textos_leg2  = {sprintf('Aspersor techo en montante (+%.1f m)', L_mont)};
    handles_leg2(end+1) = h_asp_p;
    textos_leg2{end+1}  = 'Aspersor perímetro (nivel terreno)';
    if usar_vent
        handles_leg2(end+1) = h_vent2;
        textos_leg2{end+1}  = sprintf('Nebulizador ventana (+%.1f m)', z_vent);
    end
    legend(handles_leg2, textos_leg2, 'Location','southoutside', 'FontSize',8);

    sgtitle(sprintf('Red hidráulica — %d techo + %d perímetro%s | Q=%.0f L/min · HMT=%.1f m', ...
            n_t, n_p, ternario(usar_vent, sprintf(' + %d vent', optima.n_vent), ''), ...
            optima.Q_diseno_Lmin, optima.HMT_m), 'FontSize',12, 'FontWeight','bold');

    % Guardar PNG
    try
        exportgraphics(fig, 'fig4_red_hidraulica.png', 'Resolution',150);
        fprintf('  ✓ Plano de red exportado a fig4_red_hidraulica.png\n');
    catch
        warning('No se pudo exportar el plano de la red.');
    end
end


% =====================================================================
%  AUXILIARES LOCALES
% =====================================================================
function s = ternario(cond, a, b)
    if cond, s = a; else, s = b; end
end


function p = punto_mas_cercano(contorno, q)
%PUNTO_MAS_CERCANO  Proyección de q sobre el polígono cerrado 'contorno'.
    [p, ~] = proyectar(contorno, q);
end


function nrm = normal_exterior(contorno, q)
%NORMAL_EXTERIOR  Normal unitaria del segmento más cercano a q, orientada
%   hacia afuera del polígono (alejándose del centroide).
    [~, nrm] = proyectar(contorno, q);
end


function [p, nrm] = proyectar(contorno, q)
    c = mean(contorno(1:end-1,:), 1);
    mejor = inf;  p = q;  nrm = [1 0];
    for i = 1:size(contorno,1)-1
        a  = contorno(i,:);
        b  = contorno(i+1,:);
        ab = b - a;
        t  = max(0, min(1, dot(q-a, ab) / max(dot(ab,ab), 1e-9)));
        pr = a + t*ab;
        d  = norm(q - pr);
        if d < mejor
            mejor = d;
            p = pr;
            n1 = [ab(2), -ab(1)] / max(norm(ab), 1e-9);
            if dot(n1, pr - c) < 0, n1 = -n1; end
            nrm = n1;
        end
    end
end
