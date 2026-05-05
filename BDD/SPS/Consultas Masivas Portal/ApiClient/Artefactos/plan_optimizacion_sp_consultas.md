# Plan de Optimización: spco_sop_mon_consultas_recurrentes

Este plan detalla los cambios necesarios para optimizar el procedimiento almacenado `spco_sop_mon_consultas_recurrentes`, integrando la información de actividad de emisores y mejorando el rendimiento de las consultas.

## Objetivos
1.  **Integración de Datos**: Cruzar los resultados con la vista `sat_logging..log_actividad_emisor` para mostrar la `Ultima_Fecha_Autorizacion` de cada emisor.
2.  **Optimización de Rendimiento**:
    *   Sustituir el uso de `CONVERT(date, lc_hora_registro)` por filtros de rango para permitir el uso de índices en `lc_hora_registro`.
    *   Unificar la lógica de conteo de consultas recurrentes para evitar duplicidad de código.
3.  **Mantenibilidad**: Utilizar `CREATE OR ALTER` y estandarizar el formato del código.

## Cambios Propuestos

### 1. Unificación de Lógica (Resumen de Consultas)
Se creará una lógica centralizada que maneje los filtros de `@Emisor` y `@SP` de manera dinámica, incluyendo el JOIN con `log_actividad_emisor`.

### 2. Optimización de Filtros de Fecha
Cambiar:
```sql
where convert(date, lc_hora_registro) = @Fecha
```
Por:
```sql
where lc_hora_registro >= @Fecha and lc_hora_registro < DATEADD(day, 1, @Fecha)
```

### 3. Inclusión de Datos de Actividad
Se añadirá la columna `Ultima_Fecha_Autorizacion` al conjunto de resultados de las consultas de resumen.

## Pasos de Implementación
1.  **Copia de Seguridad**: Se recomienda que el usuario realice un backup del SP actual (aunque se usará `ALTER`).
2.  **Refactorización del SP**: Aplicar los cambios en un solo bloque `ALTER PROC`.
3.  **Validación**: Ejecutar pruebas con diferentes combinaciones de parámetros.

---
**¿Desea que proceda con la implementación del código optimizado?**
