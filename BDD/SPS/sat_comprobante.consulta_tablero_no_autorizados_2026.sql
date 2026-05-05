CREATE OR ALTER PROCEDURE [dbo].[consulta_tablero_no_autorizados_2026]
    @Pais int = null,
    @Motivo bit = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @i_dias_actual INT = 3;
    DECLARE @aux_ambiente VARCHAR(50), @aux_ambiente2 VARCHAR(50);
    DECLARE @current_pais INT;
    DECLARE @total_comprobantes INT;

    -- 1. Obtener ambiente una sola vez
    EXEC sat_catalogo.dbo.sp_get_valor_variable_app 
        'sql_ambiente', @aux_ambiente OUT, @aux_ambiente2 OUT, @@SERVERNAME;

    -- 2. Identificar los países a procesar (solo los que tienen datos pendientes)
    DECLARE @paises_proceso TABLE (id_pais INT);
    INSERT INTO @paises_proceso (id_pais)
    SELECT DISTINCT co_pais
    FROM sat_comprobante..com_log_comprobante_xml WITH(NOLOCK)
    INNER JOIN sat_catalogo..sc_vista_estados_documentos ON CodigoEstatus = co_estatus
    WHERE co_hora_in > DATEADD(DAY, -@i_dias_actual, CAST(GETDATE() AS DATE)) 
      AND co_hora_in < DATEADD(HOUR, -1, GETDATE()) 
      AND Autorizado = 0
      AND co_estatus <> 14
      AND (@Pais IS NULL OR co_pais = @Pais);

    -- 3. INICIO DEL PROCESO POR PAÍS
    DECLARE cur_paises CURSOR FOR SELECT id_pais FROM @paises_proceso;
    OPEN cur_paises;
    FETCH NEXT FROM cur_paises INTO @current_pais;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Limpiar tabla temporal para cada iteración
        IF OBJECT_ID('tempdb..#resultNoAutorizados') IS NOT NULL DROP TABLE #resultNoAutorizados;

        -- 3.1 Carga Base: Solo registros del país actual
        SELECT  
            @aux_ambiente AS ambiente, co_id_emisor, co_id_comprobante, co_hora_in, co_fecha_emision, 
            co_estatus, co_num_comprobante, co_codigo_tipo_documento, co_detalle, co_numero_reprocesos,
            co_hora_reproceso, co_establecimiento, co_punto_emision, CAST(0 AS BIT) AS co_info_detalles, 
            CAST('' AS VARCHAR(500)) AS co_motivo, co_pais, CAST(0 AS BIT) AS Reprocesable,      
            DescripcionEstatus, DescripcionTipoDocumento
        INTO #resultNoAutorizados
        FROM sat_comprobante..com_log_comprobante_xml WITH(NOLOCK)
        INNER JOIN sat_catalogo..sc_vista_estados_documentos ON CodigoEstatus = co_estatus
        LEFT JOIN sat_catalogo..sc_vista_tipo_documetos ON CodigoNegocio = co_codigo_tipo_documento AND co_pais = Pais
        WHERE co_hora_in > DATEADD(DAY, -@i_dias_actual, CAST(GETDATE() AS DATE)) 
          AND co_hora_in < DATEADD(HOUR, -1, GETDATE()) 
          AND Autorizado = 0
          AND co_estatus <> 14
          AND co_pais = @current_pais;

        SELECT @total_comprobantes = COUNT(*) FROM #resultNoAutorizados;

        IF @total_comprobantes > 0
        BEGIN
            CREATE CLUSTERED INDEX IX_tmp ON #resultNoAutorizados(co_id_comprobante);

            -- 3.2 Obtención de detalles (Solo para el país actual)
            UPDATE t
            SET co_detalle = d.Mensajes, co_info_detalles = 1
            FROM #resultNoAutorizados t
            INNER JOIN (
                SELECT dl_id_comprobante, STRING_AGG(CAST(dl_mensaje AS VARCHAR(MAX)), CHAR(10)) AS Mensajes
                FROM sat_comprobante.dbo.com_detalle_log dl WITH(NOLOCK)
                WHERE dl_evento NOT IN (11,28,3,30) 
                  AND dl_mensaje NOT LIKE '%Fin proceso%' AND dl_mensaje NOT LIKE '%Consulte el detalle%'
                GROUP BY dl_id_comprobante
            ) d ON d.dl_id_comprobante = t.co_id_comprobante
            WHERE t.co_detalle IS NULL;

            -- 3.3 CURSOR DE REEMPLAZOS DINÁMICOS (Procesando solo el país actual)
            IF (@Motivo = 1 OR @total_comprobantes < 5000)
            BEGIN
                DECLARE @patron VARCHAR(1000), @reemplazo VARCHAR(200);
                DECLARE cur_reemplazos CURSOR FAST_FORWARD FOR
                SELECT patron, reemplazo FROM sat_catalogo.dbo.sc_config_reemplazos_mensaje_rechazo WHERE activo = 1 ORDER BY orden;
                
                OPEN cur_reemplazos;
                FETCH NEXT FROM cur_reemplazos INTO @patron, @reemplazo;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    -- El UPDATE ahora es instantáneo al ser una tabla temporal pequeña del país
                    UPDATE #resultNoAutorizados 
                    SET co_detalle = REPLACE(co_detalle, @patron, @reemplazo)
                    WHERE co_detalle IS NOT NULL AND co_info_detalles = 1 AND co_detalle LIKE '%' + @patron + '%';

                    FETCH NEXT FROM cur_reemplazos INTO @patron, @reemplazo;
                END
                CLOSE cur_reemplazos; DEALLOCATE cur_reemplazos;
            END

            -- 3.4 Clasificación Final del país
            UPDATE #resultNoAutorizados
            SET co_motivo = CASE
                    WHEN co_detalle LIKE '%CUFE malformado%' THEN 'CUFE mal formado'
                    WHEN co_detalle LIKE '%Digest Value%' THEN 'Digest Value'
                    WHEN co_detalle LIKE '%no coincide%' THEN 'Descuadre Valores'
                    WHEN co_detalle LIKE '%no tiene detalles%' THEN 'SIN DETALLES'
                    WHEN co_detalle LIKE '%precio unitario%' THEN 'Precio Cero'
                    WHEN co_detalle LIKE '%CABYS%' THEN 'CABYS incorrecto'
                    WHEN co_detalle LIKE '%token%' THEN 'Error TOKEN'
                    WHEN co_detalle LIKE '%Object reference%' THEN 'Error no controlado'
                    ELSE co_motivo END,
                Reprocesable = CASE WHEN co_detalle LIKE '%task was canceled%' THEN 1 ELSE 0 END;

            -- 3.5 Persistencia: Borrar país e insertar nuevos (Atómico)
            BEGIN TRANSACTION;
                DELETE FROM sat_comprobante.dbo.co_comprobante_rechazado WHERE co_pais = @current_pais;

                INSERT INTO sat_comprobante.dbo.co_comprobante_rechazado (
                    ambiente, co_motivo, co_pais, co_nemonico, co_id_emisor, co_id_comprobante, co_hora_in, 
                    co_fecha_emision, co_estatus, co_num_comprobante, co_codigo_tipo_documento, co_establecimiento, 
                    co_punto_emision, Reprocesable, co_info_detalles, co_detalle, co_ultima_actualizacion, 
                    co_numero_reprocesos, co_hora_reproceso, DescripcionEstatus, DescripcionTipoDocumento
                )
                SELECT 
                    ambiente, co_motivo, co_pais, em_nemonico, co_id_emisor, co_id_comprobante, co_hora_in, 
                    CAST(co_fecha_emision AS DATE), co_estatus, co_num_comprobante, co_codigo_tipo_documento, 
                    co_establecimiento, co_punto_emision, Reprocesable, co_info_detalles, co_detalle, GETDATE(), 
                    co_numero_reprocesos, co_hora_reproceso, DescripcionEstatus, DescripcionTipoDocumento
                FROM #resultNoAutorizados
                INNER JOIN sat_catalogo..sc_emisor ON em_id_emisor = co_id_emisor;
            COMMIT TRANSACTION;
        END

        FETCH NEXT FROM cur_paises INTO @current_pais;
    END

    CLOSE cur_paises;
    DEALLOCATE cur_paises;

    -- 4. RESULTADO FINAL CONSOLIDADO
    SELECT * FROM sat_comprobante.dbo.co_comprobante_rechazado ORDER BY co_motivo;
END;
