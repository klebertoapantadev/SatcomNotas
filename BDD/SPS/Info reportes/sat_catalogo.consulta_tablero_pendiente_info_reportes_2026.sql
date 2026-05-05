IF OBJECT_ID('[dbo].[consulta_tablero_pendiente_info_reportes_2026]') IS NOT NULL
BEGIN
    DECLARE @NombreBK NVARCHAR(255) = 'consulta_tablero_pendiente_info_reportes_2026_BK_' + REPLACE(CONVERT(VARCHAR, GETDATE(), 106), ' ', '_');
    IF OBJECT_ID(@NombreBK) IS NULL 
    BEGIN
        EXEC sp_rename 'consulta_tablero_pendiente_info_reportes_2026', @NombreBK;
        PRINT '>>> BACKUP GENERADO: ' + @NombreBK;
    END
    ELSE
    BEGIN
        PRINT '>>> BACKUP EXISTENTE: ' + @NombreBK + ' (Se omite nuevo respaldo)';
        DROP PROCEDURE [dbo].[consulta_tablero_pendiente_info_reportes_2026];
    END
END
GO
CREATE    PROC consulta_tablero_pendiente_info_reportes_2026
AS
BEGIN
    SET NOCOUNT ON; -- Evita mensajes de "filas afectadas" para mejorar el rendimiento de red



	 BEGIN TRY
	 DECLARE @inicio_proceso DATETIME = GETDATE(),
	         @NombreSP VARCHAR(200) = 'consulta_tablero_pendiente_info_reportes_2026',
			 @aux_ambiente varchar(100), @aux_ambiente2 varchar(100)
 
	 EXEC sat_catalogo.dbo.sp_get_valor_variable_app 
	'sql_ambiente', @aux_ambiente OUT, @aux_ambiente2 OUT, @@SERVERNAME;


    -- 1. Definir variables para los rangos de fecha/hora para evitar cálculos repetidos en cada fila
    DECLARE @FechaInicio DATE = CAST(DATEADD(DAY, -30, GETDATE()) AS DATE);
    DECLARE @HoraLimite DATETIME = DATEADD(MINUTE, -1, GETDATE());

	--Panama--
    SELECT 
		@aux_ambiente + '-PA' as co_ambiente,
        CAST(a.co_id_comprobante AS VARCHAR(100)) AS co_id_comprobante,
        e.em_nemonico AS co_nemonico, co_pais,
        a.co_hora_in,
        a.co_fecha_emision,
        a.co_fecha_autorizacion,
        ve.DescripcionEstatus AS co_estatus
    FROM  sat_comprobante.dbo.com_log_comprobante_xml a WITH (NOLOCK)  
    INNER JOIN sat_catalogo..sc_vista_estados_documentos ve ON ve.CodigoEstatus = a.co_estatus
    INNER JOIN sat_catalogo..sc_emisor e ON a.co_id_emisor = e.em_id_emisor    
    -- 2. Uso de WHERE EXISTS o filtros directos en lugar de JOINs pesados si solo buscamos ausencia
    WHERE a.co_pais = 507  
      AND ve.Autorizado = 1
	  AND a.co_estatus IN (4, 23, 26)    
      -- 3. Filtrado por fechas usando las variables pre-calculadas (SARGable)
      AND a.co_fecha_emision >= @FechaInicio
      AND a.co_hora_in <= @HoraLimite
	  AND a.co_fecha_emision <= getdate()
      -- 4. Lógica de exclusión optimizada
      AND (
          NOT EXISTS (SELECT 1 FROM sat_comprobante.dbo.com_aux_reportes_PA b WHERE b.Id = a.co_id_comprobante)         
      )
    union all -- Ecuador	
    SELECT   @aux_ambiente as co_ambiente,
        CAST(a.co_id_comprobante AS VARCHAR(100)) AS co_id_comprobante,
        e.em_nemonico AS co_nemonico, co_pais,
        a.co_hora_in,
        a.co_fecha_emision,
        a.co_fecha_autorizacion,
        ve.DescripcionEstatus AS co_estatus
    FROM  sat_comprobante.dbo.com_log_comprobante_xml a WITH (NOLOCK)  
    INNER JOIN sat_catalogo..sc_vista_estados_documentos ve ON ve.CodigoEstatus = a.co_estatus
    INNER JOIN sat_catalogo..sc_emisor e ON a.co_id_emisor = e.em_id_emisor    
    -- 2. Uso de WHERE EXISTS o filtros directos en lugar de JOINs pesados si solo buscamos ausencia
    WHERE a.co_pais = 593  
      AND ve.Autorizado = 1
      AND a.co_estatus NOT IN (31, 21)
      -- 3. Filtrado por fechas usando las variables pre-calculadas (SARGable)
      AND a.co_fecha_emision >= @FechaInicio
      AND a.co_hora_in <= @HoraLimite
	  AND a.co_fecha_emision <= getdate()
      -- 4. Lógica de exclusión optimizada
      AND (
          NOT EXISTS (SELECT 1 FROM sat_comprobante.dbo.com_aux_reportes_SRI b WHERE b.Id = a.co_id_comprobante)         
      )
	union all -- Costa Rica	
    SELECT   @aux_ambiente as co_ambiente,
        CAST(a.co_id_comprobante AS VARCHAR(100)) AS co_id_comprobante,
        e.em_nemonico AS co_nemonico, co_pais,
        a.co_hora_in,
        a.co_fecha_emision,
        a.co_fecha_autorizacion,
        ve.DescripcionEstatus AS co_estatus
    FROM  sat_comprobante.dbo.com_log_comprobante_xml a WITH (NOLOCK)  
    INNER JOIN sat_catalogo..sc_vista_estados_documentos ve ON ve.CodigoEstatus = a.co_estatus
    INNER JOIN sat_catalogo..sc_emisor e ON a.co_id_emisor = e.em_id_emisor    
    -- 2. Uso de WHERE EXISTS o filtros directos en lugar de JOINs pesados si solo buscamos ausencia
    WHERE a.co_pais = 506  
      AND ve.Autorizado = 1
	  -- AND a.co_estatus IN (4, 23, 26)   
      -- 3. Filtrado por fechas usando las variables pre-calculadas (SARGable)
      AND a.co_fecha_emision >= @FechaInicio
      AND a.co_hora_in <= @HoraLimite
	  AND a.co_fecha_emision <= getdate()
      -- 4. Lógica de exclusión optimizada
      AND (
          NOT EXISTS (SELECT 1 FROM sat_comprobante.dbo.com_aux_resumen_CR b WHERE b.Id = a.co_id_comprobante)         
      )
	union all -- Colombia 
	  SELECT  @aux_ambiente  as co_ambiente,
        CAST(a.co_id_comprobante AS VARCHAR(100)) AS co_id_comprobante,
        e.em_nemonico AS co_nemonico, co_pais,
        a.co_hora_in,
        a.co_fecha_emision,
        a.co_fecha_autorizacion,
        ve.DescripcionEstatus AS co_estatus
    FROM  sat_comprobante.dbo.com_log_comprobante_xml a WITH (NOLOCK)  
    INNER JOIN sat_catalogo..sc_vista_estados_documentos ve ON ve.CodigoEstatus = a.co_estatus
    INNER JOIN sat_catalogo..sc_emisor e ON a.co_id_emisor = e.em_id_emisor
    
    -- 2. Uso de WHERE EXISTS o filtros directos en lugar de JOINs pesados si solo buscamos ausencia
    WHERE a.co_pais = 57  
      AND ve.Autorizado = 1
      AND a.co_estatus NOT IN (31, 21)
      -- 3. Filtrado por fechas usando las variables pre-calculadas (SARGable)
      AND a.co_fecha_emision >= @FechaInicio
      AND a.co_hora_in <= @HoraLimite
	  AND a.co_fecha_emision <= getdate()
      -- 4. Lógica de exclusión optimizada
      AND (
          NOT EXISTS (SELECT 1 FROM sat_comprobante.dbo.com_aux_resumen_CO b WHERE b.Id = a.co_id_comprobante)
          OR 
          NOT EXISTS (SELECT 1 FROM sat_comprobante.dbo.com_informacion_impuestos c WHERE c.im_id_comprobante = a.co_id_comprobante)
      )
	  union all -- Bolivia 
	  SELECT  @aux_ambiente  as co_ambiente,
        CAST(a.co_id_comprobante AS VARCHAR(100)) AS co_id_comprobante,
        e.em_nemonico AS co_nemonico, co_pais,
        a.co_hora_in,
        a.co_fecha_emision,
        a.co_fecha_autorizacion,
        ve.DescripcionEstatus AS co_estatus
    FROM  sat_comprobante.dbo.com_log_comprobante_xml a WITH (NOLOCK)  
    INNER JOIN sat_catalogo..sc_vista_estados_documentos ve ON ve.CodigoEstatus = a.co_estatus
    INNER JOIN sat_catalogo..sc_emisor e ON a.co_id_emisor = e.em_id_emisor
    
    -- 2. Uso de WHERE EXISTS o filtros directos en lugar de JOINs pesados si solo buscamos ausencia
    WHERE a.co_pais = 591  
      AND ve.Autorizado = 1
      --AND a.co_estatus NOT IN (31, 21)
      -- 3. Filtrado por fechas usando las variables pre-calculadas (SARGable)
      AND a.co_fecha_emision >= @FechaInicio
      AND a.co_hora_in <= @HoraLimite
	  AND a.co_fecha_emision <= getdate()
      -- 4. Lógica de exclusión optimizada
      AND (
          NOT EXISTS (SELECT 1 FROM sat_comprobante.dbo.com_aux_resumen_BO b WHERE b.Id = a.co_id_comprobante)          
      )

    -- Log de éxito final
    DECLARE @fin_log DATETIME = GETDATE();
    EXEC [dbo].[spco_crear_log_consulta] 
        @i_lc_nombre_sp = @NombreSP,
        @i_lc_origen = 'BDD',
        @i_lc_inicio = @inicio_proceso,
        @i_lc_fin = @fin_log;

END TRY
BEGIN CATCH
    DECLARE @ErrorMessage NVARCHAR(MAX) = ERROR_MESSAGE();
    
    -- Log de error en auditoría
    DECLARE @fin_error DATETIME = GETDATE();
    EXEC [dbo].[spco_crear_log_consulta] 
        @i_lc_nombre_sp = @NombreSP,
        @i_lc_origen = 'BDD',
        @i_lc_inicio = @inicio_proceso,
        @i_lc_fin = @fin_error,
        @i_lc_error = @ErrorMessage;

    -- Enviar alerta a Postgres
    EXEC [master].[dbo].[spct_insertar_alerta_postgres]
        @severity = 'Error',
        @process = @NombreSP,
        @country = NULL,
        @issuing = '-',
        @message = @ErrorMessage,
        @extra_info = '{"Error": "Error en consulta tablero pendientes"}';

    THROW;
END CATCH
END
