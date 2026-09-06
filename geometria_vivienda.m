function varargout = geometria_vivienda(accion, varargin)
%GEOMETRIA_VIVIENDA  Motor paramétrico de geometría y disposición de aspersores.
%
%   Fuente ÚNICA de verdad para la planta de la vivienda. Tanto
%   graficar_layout.m como generar_epanet_inp.m lo usan, de modo que el
%   dibujo, el modelo EPANET y los parámetros hidráulicos quedan siempre
%   consistentes entre sí.
%
%   Es un "dispatcher": la primera entrada selecciona la acción.
%
%   ─────────────────────────────────────────────────────────────────────
%   geo = geometria_vivienda('construir', P)
%       Construye la geometría a partir de una estructura de disposición.
%       P puede ser:
%         • la estructura "disp" directamente, o
%         • la estructura "parametros" completa (se lee P.disp y, si existen,
%           P.ancho_franja_m y P.n_ventanas para sobrescribir).
%       Devuelve la estructura geo (ver más abajo).
%
%   pos = geometria_vivienda('distribuir_perimetro', geo, n, ancho_franja)
%       Reparte n aspersores equidistantes sobre el contorno expandido
%       (centro de la franja de defensa).
%
%   out = geometria_vivienda('expandir', poligono, d)
%       Expande un polígono cerrado una distancia d hacia afuera.
%
%   d = geometria_vivienda('default')
%       Devuelve la estructura de disposición por defecto (vivienda
%       rectangular 9.0 × 6.2 m, techo a dos aguas, 5 ventanas).
%
%   parametros = geometria_vivienda('asegurar', parametros)
%       Garantiza que parametros.disp exista. Si falta, crea una vivienda
%       rectangular cuyas dimensiones reproducen area_techo_m2 y perimetro_m
%       (para no romper el flujo de main_iterador, que no define .disp).
%   ─────────────────────────────────────────────────────────────────────
%
%   ESTRUCTURA geo:
%       geo.contorno         : polígono exterior cerrado (n×2)
%       geo.cumbreras        : cell con líneas guía del techo {[x1 y1; x2 y2], ...}
%       geo.tabiques         : cell con muros internos (vacío en modo paramétrico)
%       geo.ventanas         : cell con segmentos de ventana {[x1 y1; x2 y2], ...}
%       geo.ventanas_centros : matriz n×2 con (x,y) del centro de cada ventana
%       geo.etiquetas        : cell de structs (x,y,nombre) de ambientes
%       geo.area_techo_m2    : área proyectada del techo (polyarea del contorno)
%       geo.perimetro_m      : perímetro exterior
%       geo.area_perimetro_m2: perímetro × ancho de franja

    switch lower(accion)
        case 'construir'
            varargout{1} = construir_geometria(varargin{:});
        case 'distribuir_perimetro'
            varargout{1} = distribuir_perimetro(varargin{:});
        case 'expandir'
            varargout{1} = expandir_poligono(varargin{:});
        case 'default'
            varargout{1} = disp_default();
        case 'asegurar'
            varargout{1} = asegurar_disp(varargin{:});
        otherwise
            error('geometria_vivienda:accion', ...
                  'Acción no reconocida: "%s"', accion);
    end
end


% =====================================================================
%  DISPOSICIÓN POR DEFECTO
% =====================================================================
function d = disp_default()
    d.forma                = 'rectangular';  % 'rectangular' | 'L' | 'T'
    d.largo_m              = 9.0;     % dimensión X del bounding-box [m]
    d.ancho_m              = 10;     % dimensión Y del bounding-box [m]
    % Parámetros del saliente (solo para 'L' y 'T')
    d.saliente_x_m         = 3.0;     % X donde comienza el saliente [m]
    d.saliente_ancho_m     = 3.0;     % ancho del saliente (X) [m]
    d.saliente_largo_m     = 3.2;     % profundidad del saliente (Y) [m]
    % Techo
    d.tipo_techo           = 'plano';   % 'dos_aguas' | 'cuatro_aguas' | 'plano'
    d.orientacion_cumbrera = 'horizontal';  % 'horizontal' | 'vertical'
    % Disposición de aspersores
    d.sep_aspersores_m     = 2.0;     % separación objetivo en techo [m]
    d.sep_perimetro_m      = 2.5;     % separación objetivo en perímetro [m]
    % Defensa y ventanas (normalmente sincronizados desde 'parametros')
    d.ancho_franja_m       = 2.5;     % ancho de la franja de defensa [m]
    d.n_ventanas           = 4;       % nº de ventanas a proteger
    d.ventanas             = [];      % opcional Nx4 [x1 y1 x2 y2]; si vacío → auto
end


% =====================================================================
%  CONSTRUCCIÓN DE LA GEOMETRÍA
% =====================================================================
function geo = construir_geometria(P)
    % Normalizar entrada: aceptar 'parametros' completo o 'disp' suelto
    if isfield(P, 'disp')
        d = P.disp;
        if isfield(P, 'ancho_franja_m'), d.ancho_franja_m = P.ancho_franja_m; end
        if isfield(P, 'n_ventanas'),     d.n_ventanas     = P.n_ventanas;     end
    else
        d = P;
    end
    d = rellenar_defaults(d);

    % --- Contorno según forma ---
    switch lower(d.forma)
        case 'rectangular'
            [contorno, cumbreras] = forma_rectangular(d);
        case 'l'
            [contorno, cumbreras] = forma_L(d);
        case 't'
            [contorno, cumbreras] = forma_T(d);
        otherwise
            warning('geometria_vivienda:forma', ...
                'Forma "%s" no reconocida; se usa rectangular.', d.forma);
            [contorno, cumbreras] = forma_rectangular(d);
    end

    geo.contorno  = contorno;
    geo.cumbreras = cumbreras;
    geo.tabiques  = {};   % en modo paramétrico no se conoce el interior

    % --- Métricas derivadas (lo que antes estaba "a mano") ---
    geo.area_techo_m2     = polyarea(contorno(:,1), contorno(:,2));
    geo.perimetro_m       = perimetro_poligono(contorno);
    geo.area_perimetro_m2 = geo.perimetro_m * d.ancho_franja_m;

    % --- Ventanas ---
    if ~isempty(d.ventanas)
        [geo.ventanas, geo.ventanas_centros] = ventanas_desde_lista(d.ventanas);
    else
        [geo.ventanas, geo.ventanas_centros] = ventanas_automaticas(contorno, d.n_ventanas);
    end

    % --- Etiqueta central (un solo rótulo en modo paramétrico) ---
    cx = mean(contorno(1:end-1,1));
    cy = mean(contorno(1:end-1,2));
    geo.etiquetas = { struct('x',cx, 'y',cy, 'nombre','VIVIENDA') };
end


function d = rellenar_defaults(d)
    def = disp_default();
    campos = fieldnames(def);
    for i = 1:numel(campos)
        if ~isfield(d, campos{i}) || isempty(d.(campos{i}))
            % 'ventanas' sí puede quedar vacío (gatilla auto)
            if strcmp(campos{i}, 'ventanas'), continue; end
            d.(campos{i}) = def.(campos{i});
        end
    end
    if ~isfield(d, 'ventanas'), d.ventanas = []; end
end


function parametros = asegurar_disp(parametros)
    % Garantiza que parametros.disp exista. Si falta, crea una vivienda
    % rectangular cuyas dimensiones reproducen area_techo_m2 y perimetro_m
    % (resolviendo L+W = perim/2, L·W = area).
    if isfield(parametros, 'disp') && ~isempty(parametros.disp)
        return;
    end
    d = disp_default();
    if isfield(parametros,'area_techo_m2') && isfield(parametros,'perimetro_m')
        A = parametros.area_techo_m2;
        semiP = parametros.perimetro_m / 2;
        disc = semiP^2 - 4*A;
        if disc >= 0
            L = (semiP + sqrt(disc))/2;
            W = (semiP - sqrt(disc))/2;
            if L > 0 && W > 0
                d.largo_m = L;  d.ancho_m = W;
            end
        end
    end
    if isfield(parametros,'ancho_franja_m'), d.ancho_franja_m = parametros.ancho_franja_m; end
    if isfield(parametros,'n_ventanas'),     d.n_ventanas     = parametros.n_ventanas;     end
    parametros.disp = d;
end


% =====================================================================
%  FORMAS
% =====================================================================
function [contorno, cumbreras] = forma_rectangular(d)
    L = d.largo_m;  W = d.ancho_m;
    contorno = [0 0; L 0; L W; 0 W; 0 0];
    cumbreras = cumbreras_caja(0, 0, L, W, d);
end


function [contorno, cumbreras] = forma_L(d)
    % Rectángulo completo menos una muesca en la esquina superior derecha.
    L  = d.largo_m;  W = d.ancho_m;
    nx = min(d.saliente_ancho_m, L*0.9);   % ancho de la muesca (X)
    ny = min(d.saliente_largo_m, W*0.9);   % alto de la muesca (Y)

    contorno = [
        0      0;
        L      0;
        L      W-ny;
        L-nx   W-ny;
        L-nx   W;
        0      W;
        0      0;
    ];

    % Cumbreras en L: centro del brazo horizontal + centro del brazo vertical
    y_horiz = (W-ny)/2;                 % brazo inferior (todo el largo)
    x_vert  = (L-nx)/2;                 % brazo izquierdo (toda la altura)
    cumbreras = {
        [0, y_horiz;  L,    y_horiz];
        [x_vert, 0;   x_vert, W];
    };
    cumbreras = ajustar_cumbreras_por_tipo(cumbreras, d, 0, 0, L, W);
end


function [contorno, cumbreras] = forma_T(d)
    % Cuerpo principal arriba (todo el largo) + saliente colgando abajo,
    % centrado en saliente_x. Con los valores por defecto reproduce el
    % plano en T original (9.0 × 6.2 con saliente 3.0 × 3.2 en x=3).
    L   = d.largo_m;
    W   = d.ancho_m;
    sx  = d.saliente_x_m;
    sw  = d.saliente_ancho_m;
    sl  = d.saliente_largo_m;       % profundidad del saliente (Y)

    y_cuerpo = sl;                  % el cuerpo principal arranca en y = sl

    contorno = [
        0       y_cuerpo;
        sx      y_cuerpo;
        sx      0;
        sx+sw   0;
        sx+sw   y_cuerpo;
        L       y_cuerpo;
        L       W;
        0       W;
        0       y_cuerpo;
    ];

    % Cumbrera horizontal del cuerpo + cumbrera vertical del saliente
    y_ridge = (y_cuerpo + W)/2;
    x_ridge = sx + sw/2;
    cumbreras = {
        [0,       y_ridge;  L,       y_ridge];
        [x_ridge, 0;        x_ridge, y_ridge];
    };
end


function cumbreras = cumbreras_caja(x0, y0, L, W, d)
    % Cumbreras de un rectángulo según tipo de techo y orientación.
    cx = x0 + L/2;  cy = y0 + W/2;
    switch lower(d.tipo_techo)
        case 'plano'
            % Sin cumbrera real: dos ejes centrales en cruz como guía
            cumbreras = {
                [x0, cy;  x0+L, cy];
                [cx, y0;  cx,   y0+W];
            };
        case 'cuatro_aguas'
            % Cumbrera central acortada (hip): se ubica en el eje mayor
            if L >= W
                cumbreras = { [x0+W/2, cy;  x0+L-W/2, cy] };
            else
                cumbreras = { [cx, y0+L/2;  cx, y0+W-L/2] };
            end
        otherwise  % 'dos_aguas'
            if strcmpi(d.orientacion_cumbrera, 'vertical')
                cumbreras = { [cx, y0;  cx, y0+W] };
            else
                cumbreras = { [x0, cy;  x0+L, cy] };
            end
    end
end


function cumbreras = ajustar_cumbreras_por_tipo(cumbreras, d, x0, y0, L, W) %#ok<INUSD>
    % Para 'plano' deja la cruz tal cual; para otros tipos mantiene las
    % líneas de la L (suficiente para distribuir exactamente n aspersores).
    if strcmpi(d.tipo_techo, 'plano')
        return;
    end
end


% =====================================================================
%  VENTANAS
% =====================================================================
function [vent, centros] = ventanas_automaticas(contorno, n)
    % Coloca n ventanas equiespaciadas sobre el contorno (un segmento corto
    % tangente a la pared en cada punto) y devuelve sus centros.
    n = max(0, round(n));
    vent = {};
    centros = zeros(n, 2);
    if n == 0, centros = zeros(0,2); return; end

    [pts, tang] = puntos_sobre_contorno(contorno, n);
    ancho_vent = 1.0;   % ancho representativo de ventana [m]
    for i = 1:n
        c = pts(i,:);
        t = tang(i,:);
        p1 = c - (ancho_vent/2)*t;
        p2 = c + (ancho_vent/2)*t;
        vent{end+1} = [p1; p2]; %#ok<AGROW>
        centros(i,:) = c;
    end
end


function [vent, centros] = ventanas_desde_lista(lista)
    % lista: Nx4 [x1 y1 x2 y2]
    n = size(lista,1);
    vent = cell(1,n);
    centros = zeros(n,2);
    for i = 1:n
        p1 = lista(i,1:2);  p2 = lista(i,3:4);
        vent{i} = [p1; p2];
        centros(i,:) = (p1+p2)/2;
    end
end


% =====================================================================
%  DISTRIBUCIÓN DE ASPERSORES
% =====================================================================
function pos = distribuir_perimetro(geo, n, ancho_franja)
    % Reparte n aspersores equidistantes sobre el contorno expandido
    % (en el centro de la franja de defensa).
    n = max(1, round(n));
    contorno_offset = expandir_poligono(geo.contorno, ancho_franja/2);

    segmentos = diff(contorno_offset);
    L_seg  = sqrt(sum(segmentos.^2, 2));
    L_acum = [0; cumsum(L_seg)];
    L_total = L_acum(end);

    s = linspace(0, L_total, n+1)';
    s = s(1:end-1) + L_total/(2*n);     % desplaza media distancia
    pos = zeros(n, 2);
    for i = 1:n
        idx = find(L_acum <= s(i), 1, 'last');
        if idx >= length(L_acum), idx = length(L_acum) - 1; end
        t = (s(i) - L_acum(idx)) / max(L_seg(idx), 1e-9);
        pos(i,:) = contorno_offset(idx,:) + ...
                   t * (contorno_offset(idx+1,:) - contorno_offset(idx,:));
    end
end


% =====================================================================
%  UTILIDADES GEOMÉTRICAS
% =====================================================================
function P = perimetro_poligono(poly)
    d = diff(poly);
    P = sum(sqrt(sum(d.^2, 2)));
end


function [pts, tang] = puntos_sobre_contorno(contorno, n)
    % n puntos equiespaciados sobre el contorno cerrado, con su tangente.
    seg = diff(contorno);
    Ls  = sqrt(sum(seg.^2, 2));
    L_acum = [0; cumsum(Ls)];
    L_total = L_acum(end);

    s = linspace(0, L_total, n+1)';
    s = s(1:end-1) + L_total/(2*n);
    pts = zeros(n, 2);
    tang = zeros(n, 2);
    for i = 1:n
        idx = find(L_acum <= s(i), 1, 'last');
        if idx >= length(L_acum), idx = length(L_acum) - 1; end
        tt = (s(i) - L_acum(idx)) / max(Ls(idx), 1e-9);
        pts(i,:) = contorno(idx,:) + tt * (contorno(idx+1,:) - contorno(idx,:));
        d = contorno(idx+1,:) - contorno(idx,:);
        tang(i,:) = d / max(norm(d), 1e-9);
    end
end


function out = expandir_poligono(poly, d)
%EXPANDIR_POLIGONO  Expande un polígono cerrado una distancia d hacia afuera.
%   Usa polybuffer (R2017b+) y si no está disponible recurre a un método
%   manual por bisectrices exteriores.
    try
        ps = polyshape(poly(:,1), poly(:,2), 'Simplify', false);
        ps_off = polybuffer(ps, d, 'JointType', 'square');
        V = ps_off.Vertices;
        out = [V; V(1,:)];
    catch
        n = size(poly,1) - 1;   % se asume último punto = primero
        out = zeros(size(poly));
        for i = 1:n
            prev = poly(mod(i-2,n)+1, :);
            curr = poly(i, :);
            next = poly(mod(i,n)+1, :);
            v1 = (curr - prev) / max(norm(curr - prev), 1e-9);
            v2 = (next - curr) / max(norm(next - curr), 1e-9);
            nrm1 = [v1(2), -v1(1)];
            nrm2 = [v2(2), -v2(1)];
            bisec = (nrm1 + nrm2) / max(norm(nrm1 + nrm2), 1e-9);
            out(i,:) = curr + d * bisec;
        end
        out(end,:) = out(1,:);
    end
end
