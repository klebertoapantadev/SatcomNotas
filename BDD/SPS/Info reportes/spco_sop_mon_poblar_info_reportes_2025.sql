IF OBJECT_ID('[dbo].[spco_sop_mon_poblar_info_reportes_2025]') IS NOT NULL
BEGIN
    DECLARE @NombreBK NVARCHAR(255) = 'spco_sop_mon_poblar_info_reportes_2025_BK_' + REPLACE(CONVERT(VARCHAR, GETDATE(), 106), ' ', '_');
    IF OBJECT_ID(@NombreBK) IS NULL 
    BEGIN
        EXEC sp_rename 'spco_sop_mon_poblar_info_reportes_2025', @NombreBK;
        PRINT '>>> BACKUP GENERADO: ' + @NombreBK;
    END
    ELSE
    BEGIN
        PRINT '>>> BACKUP EXISTENTE: ' + @NombreBK + ' (Se omite nuevo respaldo)';
        DROP PROCEDURE [dbo].[spco_sop_mon_poblar_info_reportes_2025];
    END
END
GO
CREATE PROCEDURE [dbo].[spco_sop_mon_poblar_info_reportes_2025]    
    @pais INT = NULL,    
    @id_emisor INT = NULL, -- No se usa en el código original, pero se mantiene la firma    
    @FechaProceso DATE = NULL,    
    @BitBorrar BIT = 0 -- Control para borrar    
-- exec [spco_sop_mon_poblar_info_reportes_2025] 57, null, '2025-04-29'    
-- exec [spco_sop_mon_poblar_info_reportes_2025] 593, null, '2025-12-02'    
-- exec [spco_sop_mon_poblar_info_reportes_2025] null, null, '2025-12-02'    
  
AS    
BEGIN    
    SET NOCOUNT ON;    
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;    
    
    BEGIN TRY
    
    DECLARE @inicio_proceso DATETIME = GETDATE(),
            @params NVARCHAR(MAX);

    SET @params = CONCAT('@pais: ', ISNULL(CAST(@pais AS VARCHAR), 'NULL'), 
                         ', @id_emisor: ', ISNULL(CAST(@id_emisor AS VARCHAR), 'NULL'), 
                         ', @FechaProceso: ', ISNULL(CAST(@FechaProceso AS VARCHAR), 'NULL'), 
                         ', @BitBorrar: ', ISNULL(CAST(@BitBorrar AS VARCHAR), 'NULL'));

    DECLARE @inicio DATETIME = GETDATE(),    
            @LoteSize INT = 2000,    
            @Contador INT = 1,    
            @FechaDesde DATETIME,    
            @FechaHasta DATETIME;    
    
    -- Validación de fecha obligatoria para optimización de rango    
    IF @FechaProceso IS NULL    
    BEGIN    
        PRINT 'La fecha de proceso es obligatoria para optimizar la consulta.';    
        RETURN;    
    END    
    
    -- Configurar rango de fechas para hacer la consulta SARGable (Index Seek en lugar de Scan)    
    SET @FechaDesde = CAST(@FechaProceso AS DATETIME);    
    SET @FechaHasta = DATEADD(DAY, 1, @FechaDesde);    
    
    -- Tabla temporal ligera solo con lo necesario    
    CREATE TABLE #t_ComprobantesAll (    
        IdComprobante BIGINT PRIMARY KEY, -- Clustered Index implícito para velocidad máxima    
        au_pais INT,    
        au_tipo INT    
    );    
    
    -------------------------------------------------------------------------    
    -- 1. IDENTIFICACIÓN DE COMPROBANTES A PROCESAR (Llenado de tabla temporal)    
    -------------------------------------------------------------------------    
        
    -- COLOMBIA (57)    
    IF (@pais = 57 OR @pais IS NULL)    
    BEGIN    
        INSERT INTO #t_ComprobantesAll (IdComprobante, au_pais, au_tipo)    
        SELECT  distinct   
            a.co_id_comprobante,    
            a.co_pais,    
            a.co_codigo_tipo_documento    
        FROM com_log_comprobante_xml a WITH (NOLOCK)    
        LEFT JOIN com_aux_resumen_CO b WITH (NOLOCK) ON a.co_id_comprobante = b.Id    
        LEFT JOIN com_informacion_impuestos c WITH (NOLOCK) ON a.co_id_comprobante = c.im_id_comprobante -- Corregido join directo a la tabla A para eficiencia    
        WHERE a.co_pais = 57             
		  --AND a.co_fecha_emision >= @FechaDesde AND a.co_fecha_emision < @FechaHasta -- Optimización de índice    
		  AND a.co_fecha_in >= @FechaDesde AND a.co_fecha_in < @FechaHasta -- Optimización de índice    
          AND a.co_estatus IN (SELECT codigo FROM sat_catalogo..sc_vista_estados_autorizados)    
          AND (b.Id IS NULL OR c.im_id_comprobante IS NULL);    
    
        PRINT dbo.fn_get_text_dif(@inicio, @@ROWCOUNT, CONCAT('Consulta COLOMBIA Día ', @FechaProceso));    
    END    
    
    -- ECUADOR (593)    
    IF (@pais = 593 OR @pais IS NULL)    
    BEGIN    
        INSERT INTO #t_ComprobantesAll (IdComprobante, au_pais, au_tipo)    
        SELECT distinct    
            a.co_id_comprobante,    
            a.co_pais,    
            a.co_tipo_comprobante    
        FROM com_log_comprobante_xml a WITH (NOLOCK)    
        LEFT JOIN com_aux_reportes_SRI b WITH (NOLOCK) ON a.co_id_comprobante = b.Id    
        WHERE a.co_pais = 593    
          AND a.co_fecha_in >= @FechaDesde AND a.co_fecha_in < @FechaHasta    
          AND a.co_estatus IN (4, 23, 26) -- IDs directos suelen ser más rápidos que subconsultas si son estáticos    
          AND a.co_estatus IN (SELECT codigo FROM sat_catalogo..sc_vista_estados_autorizados) -- Doble chequeo mantenido del original    
          AND b.Id IS NULL;    
    
        PRINT dbo.fn_get_text_dif(@inicio, @@ROWCOUNT, CONCAT('Consulta ECUADOR Día ', @FechaProceso));    
    END    
    
    -- COSTA RICA (506)    
    IF (@pais = 506 OR @pais IS NULL)    
    BEGIN    
        INSERT INTO #t_ComprobantesAll (IdComprobante, au_pais, au_tipo)    
        SELECT   distinct  
            a.co_id_comprobante,    
            a.co_pais,    
            a.co_tipo_comprobante    
        FROM com_log_comprobante_xml a WITH (NOLOCK)    
        LEFT JOIN com_aux_resumen_CR b WITH (NOLOCK) ON a.co_id_comprobante = b.Id    
        WHERE a.co_pais = 506    
          AND a.co_fecha_in >= @FechaDesde AND a.co_fecha_in < @FechaHasta    
          AND a.co_estatus IN (4, 23, 26)    
          AND b.Id IS NULL;    
    
        PRINT dbo.fn_get_text_dif(@inicio, @@ROWCOUNT, CONCAT('Consulta CR Día ', @FechaProceso));    
    END    
    
    -- PANAMA (507)    
    IF (@pais = 507 OR @pais IS NULL)    
    BEGIN    
        INSERT INTO #t_ComprobantesAll (IdComprobante, au_pais, au_tipo)    
        SELECT     distinct
            a.co_id_comprobante,    
            a.co_pais,    
            a.co_tipo_comprobante    
        FROM com_log_comprobante_xml a WITH (NOLOCK)    
        LEFT JOIN com_aux_reportes_PA b WITH (NOLOCK) ON a.co_id_comprobante = b.Id    
        WHERE a.co_pais = 507    
          AND a.co_fecha_in >= @FechaDesde AND a.co_fecha_in < @FechaHasta    
          AND a.co_estatus IN (4, 23, 26)    
          AND b.Id IS NULL;    
    
        PRINT dbo.fn_get_text_dif(@inicio, @@ROWCOUNT, CONCAT('Consulta PA Día ', @FechaProceso));    
    END    
    
-- Honduras (504)    
    IF (@pais = 504 OR @pais IS NULL)    
    BEGIN    
        INSERT INTO #t_ComprobantesAll (IdComprobante, au_pais, au_tipo)    
        SELECT distinct    
            a.co_id_comprobante,    
            a.co_pais,    
            a.co_codigo_tipo_documento    
        FROM com_log_comprobante_xml a WITH (NOLOCK)    
        LEFT JOIN com_aux_reportes_HN b WITH (NOLOCK) ON a.co_id_comprobante = b.Id    
        WHERE a.co_pais = 504    
          AND a.co_fecha_in >= @FechaDesde AND a.co_fecha_in < @FechaHasta -- Optimización de índice    
          AND a.co_estatus not IN (14)    
          AND b.Id IS NULL ;    
    
        PRINT dbo.fn_get_text_dif(@inicio, @@ROWCOUNT, CONCAT('Consulta Honduras ', @FechaProceso));    
    END    
    -------------------------------------------------------------------------    
    -- 2. BUCLE DE PROCESAMIENTO (Staging Table)    
    -------------------------------------------------------------------------    
        
    WHILE EXISTS (SELECT 1 FROM #t_ComprobantesAll)    
    BEGIN    
        SET @inicio = GETDATE();    
    
        -- Limpiar tabla de paso (Staging)    
        TRUNCATE TABLE com_comprobante_aux;    
    
        -- Poblar tabla de paso con el lote actual    
        -- Usamos TOP y un JOIN eficiente contra la PK de la tabla temporal    
        INSERT INTO com_comprobante_aux (    
            co_id_comprobante, co_codigo_tipo_documento, co_trama_dto, co_id_emisor, co_pais,     
            co_fecha_emision, Info, co_es_nota_credito, co_num_comprobante,     
            co_clave_acceso, co_num_autorizacion, co_total_comprobante    
        )    
        SELECT TOP (@LoteSize)    
            com.co_id_comprobante,    
            com.co_codigo_tipo_documento,    
            com.co_trama_dto,    
            com.co_id_emisor,    
            com.co_pais,    
            com.co_fecha_emision,    
            CONCAT('Poblado ', @FechaProceso, ' Bucle:', @Contador),    
            CASE     
                WHEN doc.Documento LIKE '%CREDITO%' OR doc.Documento LIKE '%DEBITO%'  OR doc.Documento LIKE 'Recibo elect%' THEN 1     
                ELSE 0     
            END,    
            com.co_num_comprobante,    
            com.co_clave_acceso,    
            com.co_num_autorizacion,    
            com.co_total_comprobante    
        FROM #t_ComprobantesAll aux    
        INNER JOIN com_log_comprobante_xml com WITH (NOLOCK)     
            ON com.co_id_comprobante = aux.IdComprobante     
            -- No necesitamos JOIN por pais/tipo si el ID es único (PK), lo cual es más rápido.    
        LEFT JOIN sat_catalogo.dbo.sc_vista_tipo_documetos doc WITH (NOLOCK)    
            ON com.co_codigo_tipo_documento = doc.CodigoNegocio     
            AND com.co_pais = doc.Pais;    
    
        PRINT dbo.fn_get_text_dif(@inicio, @@ROWCOUNT, CONCAT('Llena aux comprobantes: ', @FechaProceso));    
    
       -- Si por alguna razón no insertó nada (error de integridad, etc), rompemos para evitar bucle infinito    
        IF NOT EXISTS (SELECT 1 FROM com_comprobante_aux)     
        BEGIN    
            BREAK;     
        END    
    
        ---------------------------------------------------------------------    
        -- Ejecución de Sub-Procedimientos    
        ---------------------------------------------------------------------    
            
        EXEC [spco_sop_mon_poblar_info_clientes_2025] @BitBorrar;    
        PRINT dbo.fn_get_text_dif(@inicio, 0, CONCAT('#', @Contador, ') Main DatosCliente'));    
    
        EXEC [spco_sop_mon_poblar_impuestos_todos_2025] @BitBorrar;    
        PRINT dbo.fn_get_text_dif(@inicio, 0, 'Main Impuestos');    
    
        EXEC spco_sop_mon_poblar_fpagos_todos_2025 @BitBorrar;    
        PRINT dbo.fn_get_text_dif(@inicio, 0, 'Main Formas de pago');    
    
        EXEC spco_sop_mon_poblar_info_adicional_todos_2025 @BitBorrar;    
        PRINT dbo.fn_get_text_dif(@inicio, 0, 'Main Info Adicional');    
    
        EXEC spco_sop_mon_poblar_documento_asociado_todos_2025 @BitBorrar;    
        PRINT dbo.fn_get_text_dif(@inicio, 0, 'Main Doc Asociado');    
    
  EXEC spco_sop_poblar_retenciones_aux_2025 @BitBorrar;    
        PRINT dbo.fn_get_text_dif(@inicio, 0, 'Main Retenciones');    
        -- Procesos específicos por país    
        IF (@pais IS NULL OR @pais = 57)     
            EXEC spco_sop_poblar_tabla_aux_col2025 @BitBorrar;    
    
        IF (@pais IS NULL OR @pais = 593)     
            EXEC [spco_sop_poblar_tabla_aux_ec2025] @BitBorrar;    
    
        IF (@pais IS NULL OR @pais = 506)     
            EXEC [spco_sop_poblar_tabla_aux_cr2025] @BitBorrar;    
    
        IF (@pais IS NULL OR @pais = 507)     
            EXEC [spco_sop_poblar_tabla_aux_pa2025] @BitBorrar;    
  
  IF (@pais IS NULL OR @pais = 504)     
            EXEC [spco_sop_poblar_tabla_aux_hn2025] @BitBorrar;    
        ---------------------------------------------------------------------    
        -- Limpieza de Lote Procesado    
        ---------------------------------------------------------------------    
    
        -- Borramos de la temporal los IDs que ya procesamos (los que están en la tabla física aux)    
        DELETE T1     
        FROM #t_ComprobantesAll AS T1    
        INNER JOIN com_comprobante_aux AS T2 ON T1.IdComprobante = T2.co_id_comprobante;    
    
        PRINT dbo.fn_get_text_dif(@inicio, @@ROWCOUNT, CONCAT('Borra procesados ', @FechaProceso));    
            
        SET @Contador = @Contador + 1;    
    END    
    
    -- Log de éxito final
    DECLARE @fin_log DATETIME = GETDATE();
    EXEC [dbo].[spco_crear_log_consulta] 
        @i_lc_nombre_sp = 'spco_sop_mon_poblar_info_reportes_2025',
        @i_lc_emisor = @id_emisor,
        @i_lc_parametros = @params,
        @i_lc_origen = 'BDD',
        @i_lc_inicio = @inicio_proceso,
        @i_lc_fin = @fin_log;

    RETURN 0;    
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(MAX) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        -- Log de error en auditoría
        DECLARE @fin_error DATETIME = GETDATE();
        EXEC [dbo].[spco_crear_log_consulta] 
            @i_lc_nombre_sp = 'spco_sop_mon_poblar_info_reportes_2025',
            @i_lc_emisor = @id_emisor,
            @i_lc_parametros = @params,
            @i_lc_origen = 'BDD',
            @i_lc_inicio = @inicio_proceso,
            @i_lc_fin = @fin_error,
            @i_lc_error = @ErrorMessage;

        -- Enviar alerta a Postgres
        EXEC [master].[dbo].[spct_insertar_alerta_postgres]
            @severity = 'Error',
            @process = 'spco_sop_mon_poblar_info_reportes_2025',
            @country = @pais,
            @issuing = '-',
            @message = @ErrorMessage,
            @extra_info = '{"Error": "Error en población de info reportes"}';

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END    
