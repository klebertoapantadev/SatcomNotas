USE [sat_logging]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
=========================================================================================
PROCEDIMIENTO: [dbo].[spco_sop_mon_consultas_recurrentes]
AUTOR: Antigravity (Optimización)
FECHA: 2026-05-04
PROPÓSITO: Monitoreo de consultas recurrentes en BDD con información de actividad de emisores.
=========================================================================================
*/

CREATE OR ALTER PROC [dbo].[spco_sop_mon_consultas_recurrentes]
    @Fecha DATE = NULL,
    @Emisor INT = NULL,
    @SP VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Default a la fecha actual si es nulo
    IF (@Fecha IS NULL) SELECT @Fecha = GETDATE();

    -- Definimos los límites de tiempo para optimizar el uso de índices (SARGability)
    DECLARE @FechaInicio DATETIME = CAST(@Fecha AS DATETIME);
    DECLARE @FechaFin DATETIME = DATEADD(DAY, 1, @FechaInicio);

    ---------------------------------------------------------------------------
    -- 1. CONSULTA DE RESUMEN (RECURRENTES)
    -- Cruzada con sat_logging..log_actividad_emisor
    ---------------------------------------------------------------------------
    SELECT 
        COUNT(1) AS NumConsultas,
        E.em_nombre,
        E.em_nemonico,
        E.em_pais,
        L.lc_nombre_sp,
        L.lc_emisor,
        -- Lógica de parámetros según rama original
        CASE 
            WHEN @Emisor IS NOT NULL AND @SP IS NULL THEN dbo.fn_get_scrip_sp(L.lc_parametros) 
            ELSE L.lc_parametros 
        END AS lc_parametros,
        L.lc_usuario,
        A.Ultima_Fecha_Autorizacion AS Ultima_Fecha_Trx_Autorizada
    FROM sat_logging.dbo.com_log_consultas_bdd L WITH(NOLOCK)
    LEFT JOIN sat_catalogo.dbo.sc_emisor E ON L.lc_emisor = E.em_id_emisor
    LEFT JOIN sat_logging..log_actividad_emisor A ON A.ID_Emisor = L.lc_emisor
    WHERE L.lc_hora_registro >= @FechaInicio AND L.lc_hora_registro < @FechaFin
      AND (@Emisor IS NULL OR L.lc_emisor = @Emisor)
      AND (@SP IS NULL OR L.lc_nombre_sp LIKE '%' + @SP + '%')
    GROUP BY 
        E.em_nombre,
        E.em_nemonico,
        E.em_pais,
        L.lc_nombre_sp,
        L.lc_emisor,
        CASE 
            WHEN @Emisor IS NOT NULL AND @SP IS NULL THEN dbo.fn_get_scrip_sp(L.lc_parametros) 
            ELSE L.lc_parametros 
        END,
        L.lc_usuario,
        A.Ultima_Fecha_Autorizacion
    HAVING COUNT(1) > 3
    ORDER BY NumConsultas DESC;

    ---------------------------------------------------------------------------
    -- 2. CONSULTAS DE DETALLE (Mantiene lógica de ramas originales)
    ---------------------------------------------------------------------------
    
    -- Rama: Solo SP (o SP y Emisor)
    IF (@SP IS NOT NULL)
    BEGIN
        SELECT 
            DATEDIFF(SECOND, lc_inicio, lc_fin) AS [Tiempo (s)], 
            *
        FROM sat_logging.dbo.com_log_consultas_bdd WITH(NOLOCK)
        WHERE lc_hora_registro >= @FechaInicio AND lc_hora_registro < @FechaFin
          AND lc_nombre_sp = @SP
          AND (@Emisor IS NULL OR lc_emisor = @Emisor)
        ORDER BY lc_hora_registro DESC;
    END
    -- Rama: General (Sin parámetros específicos)
    ELSE IF (@Emisor IS NULL AND @SP IS NULL)
    BEGIN
        SELECT 
            DATEDIFF(MILLISECOND, lc_inicio, lc_fin) AS [Tiempo (ms)], 
            *
        FROM sat_logging.dbo.com_log_consultas_bdd WITH(NOLOCK)
        WHERE lc_hora_registro >= @FechaInicio AND lc_hora_registro < @FechaFin
        ORDER BY [Tiempo (ms)] DESC;
    END

END
GO
