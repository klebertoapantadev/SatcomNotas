# Proceso de Información de Reportes (2025-2026)

Este documento explica la estructura, dependencias y el sistema de monitoreo/alertas de los procedimientos almacenados encargados de poblar la información de reportes en Satcom.

## 1. Flujo de Ejecución y Dependencias

El proceso está diseñado de forma modular, con un orquestador principal que delega la población de datos en sub-procesos específicos.

### Jerarquía de Llamadas:
1.  **`spct_reproceso_resumen_by_pais`**: Punto de entrada que verifica el entorno (Hosting vs Local) para evitar ejecuciones accidentales en producción fuera del JOB programado.
2.  **`spct_reproceso_resumen_by_pais_hosting`**: Controla el bucle de fechas (por defecto los últimos 5 días) y gestiona el control de ejecución única.
3.  **`spco_sop_mon_poblar_info_reportes_2025`**: Orquestador de la población. Divide el trabajo en lotes y llama a los sub-procesos de:
    *   Clientes
    *   Impuestos
    *   Formas de Pago
    *   Información Adicional
    *   Documentos Asociados
    *   Retenciones
    *   Tablas auxiliares por país (EC, CO, CR, PA, HN).
4.  **`spco_sop_mon_genera_campos_reporte`**: Proceso final que genera campos calculados específicos para la visualización de reportes.

## 2. Monitoreo y Alertas (Postgres)

Se ha implementado un sistema de alertas proactivo que notifica fallos de ejecución directamente a la base de datos de Postgres (utilizada para el helpdesk y monitoreo centralizado).

### Implementación Técnica:
Cada proceso principal está envuelto en un bloque `TRY...CATCH`. En caso de error, se invoca el procedimiento:
`[master].[dbo].[spct_insertar_alerta_postgres]`

**Parámetros enviados:**
*   `@severity`: 'Error'
*   `@process`: Nombre del SP que falló.
*   `@country`: País afectado.
*   `@message`: Mensaje técnico del error (`ERROR_MESSAGE()`).

## 3. Tablero de Dashboard (Pendientes)

El tablero de **Pendientes de Reporte 2026** consume datos del siguiente procedimiento:
*   **Procedimiento:** `consulta_tablero_pendiente_info_reportes_2026`
*   **Propósito:** Mostrar los comprobantes que están autorizados pero cuya información aún no ha sido procesada por los SPs de "Info Reportes".

## 4. Ejemplos de Ejecución (Soporte)

### Reproceso Manual (Por País y Rango de Fechas):
```sql
-- Reprocesar Colombia del 1 al 5 de Mayo de 2026
EXEC sat_comprobante.dbo.spct_reproceso_resumen_by_pais 
    @pais = 57, 
    @borrar = 1, 
    @fechaInicio = '2026-05-01', 
    @fechaFin = '2026-05-05';
```

### Ejecución de Población Directa (Lote Único):
```sql
-- Poblar un día específico para Ecuador
EXEC sat_comprobante.dbo.spco_sop_mon_poblar_info_reportes_2025 
    @pais = 593, 
    @FechaProceso = '2026-05-04', 
    @BitBorrar = 0;
```

### Consulta de Control de Ejecución:
Si un proceso parece "pegado", verificar la tabla de control:
```sql
SELECT * FROM sat_comprobante.dbo.com_control_ejecucion;
```
