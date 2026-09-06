function BD = cargar_BD(archivo_aspersores, archivo_tuberias, archivo_bombas)
%CARGAR_BD  Carga las tres bases de datos del proyecto desde archivos Excel.
%
%   BD = cargar_BD(archivo_aspersores, archivo_tuberias, archivo_bombas)
%   retorna una estructura con tres campos:
%       BD.aspersores : table con catálogo de aspersores
%       BD.tuberias   : table con catálogo de tuberías
%       BD.bombas     : table con catálogo de bombas (incluye curvas)
%
%   Las curvas de bomba (Curva_Q_Lmin / Curva_H_m) se almacenan como
%   strings con valores separados por ';' en el Excel y se convierten
%   a vectores numéricos en columnas adicionales:
%       BD.bombas.Q_curva : cell array con vectores de caudal
%       BD.bombas.H_curva : cell array con vectores de altura
%
%   Así pueden interpolarse luego en seleccionar_bomba para encontrar
%   el punto de operación real.

    % --- Aspersores ---
    BD.aspersores = readtable(archivo_aspersores, ...
                              'Sheet', 'Aspersores', ...
                              'VariableNamingRule', 'preserve');

    % --- Tuberías ---
    BD.tuberias = readtable(archivo_tuberias, ...
                            'Sheet', 'Tuberias', ...
                            'VariableNamingRule', 'preserve');

    % --- Bombas ---
    BD.bombas = readtable(archivo_bombas, ...
                          'Sheet', 'Bombas', ...
                          'VariableNamingRule', 'preserve');

    % Convertir curvas string → vectores numéricos
    n_bombas = height(BD.bombas);
    Q_curva  = cell(n_bombas, 1);
    H_curva  = cell(n_bombas, 1);
    for i = 1:n_bombas
        Q_str = BD.bombas.Curva_Q_Lmin{i};
        H_str = BD.bombas.Curva_H_m{i};
        Q_curva{i} = str2double(strsplit(Q_str, ';'));
        H_curva{i} = str2double(strsplit(H_str, ';'));
    end
    BD.bombas.Q_curva = Q_curva;
    BD.bombas.H_curva = H_curva;

    % --- Verificación rápida ---
    if any(isnan(BD.aspersores.K_factor))
        warning('cargar_BD:nanK', ...
            'Hay K_factor NaN en BD_Aspersores. Revisar la planilla.');
    end
end
