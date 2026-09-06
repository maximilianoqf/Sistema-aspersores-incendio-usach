# Sistema de dimensionamiento hidráulico contra incendios forestales

Código MATLAB desarrollado como parte de la tesis de Ingeniería Mecánica de
**Maximiliano Quintanilla** (Universidad de Santiago de Chile). Dimensiona un
sistema de aspersión perimetral y de techo para proteger viviendas frente a
incendios forestales, acoplando un modelo de fuego (Rothermel–Byram) con un
optimizador hidráulico que itera sobre catálogos reales de aspersores, tuberías
y bombas.

## Contenido

- **GUI principal** — `gui_sistema_incendio.m`
  Interfaz con 7 pestañas: vivienda, modelo de fuego, criterios, iteración y
  bombas, resultados, editor de BDs y comparador de escenarios.
- **Modelo de fuego** — `calcular_fuego.m`
  Rothermel 1972 / Albini 1976 → Byram → factor de vista → Beer–Lambert →
  balance de energía. Deriva densidad de aspersión y tiempo de operación.
- **Optimizador** — `iterar_configuraciones.m`, `evaluar_configuracion.m`
  Recorre el espacio de diseño (aspersores × diámetros × bombas) y evalúa
  cada combinación con el modelo hidráulico completo (anillo perimetral +
  montantes de techo + ramales de perímetro).
- **Selección de bombas** — `seleccionar_grupo_bombas.m`,
  `bombas_construir_cache.m`, `preparar_pumps.m`, `limite_caudal_aspersores.m`
- **Utilidades** — `cargar_BD.m`, `geometria_vivienda.m`,
  `generar_cotizacion.m`, `generar_epanet_inp.m`, `obtener.m`
- **Gráficos** — `graficar_layout.m`, `graficar_red_hidraulica.m`,
  `graficar_resultados.m`
- **Bases de datos** — `BD_Aspersores.xlsx`, `BD_Bombas.xlsx`,
  `BD_Tuberias.xlsx`

## Requisitos

- MATLAB R2021b o superior (usa `uifigure` y controles de App Designer).
- Toolbox base; no requiere toolboxes de optimización.

## Uso

```matlab
>> gui_sistema_incendio
```

La GUI carga las tres bases de datos `.xlsx` desde la misma carpeta, permite
editar parámetros, ejecutar la iteración y exportar resultados a Excel o a un
archivo `.inp` de EPANET.

## Licencia

MIT — ver [LICENSE](LICENSE).

## Cómo citar

Quintanilla, M. (2026). *Sistema de dimensionamiento hidráulico contra
incendios forestales para viviendas rurales* [Tesis de pregrado, Universidad
de Santiago de Chile].
