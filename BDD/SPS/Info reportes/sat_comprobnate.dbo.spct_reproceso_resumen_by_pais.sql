Text
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('[dbo].[spct_reproceso_resumen_by_pais]') IS NOT NULL
BEGIN
    DECLARE @NombreBK NVARCHAR(255) = 'spct_reproceso_resumen_by_pais_BK_' + REPLACE(CONVERT(VARCHAR, GETDATE(), 106), ' ', '_');
    IF OBJECT_ID(@NombreBK) IS NULL 
    BEGIN
        EXEC sp_rename 'spct_reproceso_resumen_by_pais', @NombreBK;
        PRINT '>>> BACKUP GENERADO: ' + @NombreBK;
    END
    ELSE
    BEGIN
        PRINT '>>> BACKUP EXISTENTE: ' + @NombreBK + ' (Se omite nuevo respaldo)';
        DROP PROCEDURE [dbo].[spct_reproceso_resumen_by_pais];
    END
END
GO
CREATE   PROCEDURE [dbo].[spct_reproceso_resumen_by_pais]                     
    @pais int = null   
    ,@borrar bit = 0 
    ,@fechaFin date = null  
    ,@fechaInicio date = null  
AS               
BEGIN
	BEGIN TRY
	DECLARE @inicio_proceso DATETIME = GETDATE(),
	        @NombreSP VARCHAR(200) = 'spct_reproceso_resumen_by_pais',
            @params NVARCHAR(MAX);

    SET @params = CONCAT('@pais: ', ISNULL(CAST(@pais AS VARCHAR), 'NULL'), 
                         ', @borrar: ', ISNULL(CAST(@borrar AS VARCHAR), 'NULL'), 
                         ', @fechaFin: ', ISNULL(CAST(@fechaFin AS VARCHAR), 'NULL'), 
                         ', @fechaInicio: ', ISNULL(CAST(@fechaInicio AS VARCHAR), 'NULL'));

    -- Declaramos la variable para capturar el nombre de la BDD
    DECLARE @nombreBDD NVARCHAR(128) = DB_NAME();

	--select @@SERVERNAME
    -- Validación: Verifica servidor Y nombre de la base de datos
    IF ((@@SERVERNAME = 'SRVBDDMSPROD\MSPROD2022' or @@SERVERNAME = 'EC2AMAZ-IVL1JSC' )AND @nombreBDD = 'sat_comprobante')
    BEGIN
        PRINT 'Ejecución cancelada: Hosting trabaja con JOB en el entorno de producción: ' + @nombreBDD;
        
        -- Log de cancelación como éxito informativo
        DECLARE @fin_cancel DATETIME = GETDATE();
        EXEC [dbo].[spco_crear_log_consulta] 
            @i_lc_nombre_sp = @NombreSP,
            @i_lc_origen = 'BDD',
            @i_lc_inicio = @inicio_proceso,
            @i_lc_fin = @fin_cancel,
            @i_lc_error = 'Ejecución cancelada por restricciones de entorno (Hosting/JOB)';
            
        RETURN 0;
    END
    ELSE
    BEGIN
        -- Si no es el entorno restringido, ejecuta el procedimiento remoto
        EXEC sat_comprobante.dbo.spct_reproceso_resumen_by_pais_hosting 
            @pais, @borrar, @fechaFin, @fechaInicio;

        -- Log de éxito final
        DECLARE @fin_log DATETIME = GETDATE();
        EXEC [dbo].[spco_crear_log_consulta] 
            @i_lc_nombre_sp = @NombreSP,
            @i_lc_origen = 'BDD',
            @i_lc_inicio = @inicio_proceso,
            @i_lc_fin = @fin_log;
    END
    END
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
			@country = @pais,
			@issuing = '-',
			@message = @ErrorMessage,
			@extra_info = '{"Error": "Error en reproceso resumen pais"}';

		THROW;
	END CATCH
END



Completion time: 2026-05-04T10:12:50.2074171-05:00
