function v = obtener(s, campo, def)
%OBTENER  Devuelve s.(campo) si existe y no está vacío; si no, el default.
%   Helper compartido usado por iterar_configuraciones, limite_caudal_aspersores,
%   generar_cotizacion, generar_epanet_inp y graficar_red_hidraulica.
    if isfield(s, campo) && ~isempty(s.(campo))
        v = s.(campo);
    else
        v = def;
    end
end
