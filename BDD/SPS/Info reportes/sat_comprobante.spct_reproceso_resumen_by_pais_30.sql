Text
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('[dbo].[spct_reproceso_resumen_by_pais_30]') IS NOT NULL
BEGIN
    DECLARE @NombreBK NVARCHAR(255) = 'spct_reproceso_resumen_by_pais_30_BK_' + REPLACE(CONVERT(VARCHAR, GETDATE(), 106), ' ', '_');
    IF OBJECT_ID(@NombreBK) IS NULL 
    BEGIN
        EXEC sp_rename 'spct_reproceso_resumen_by_pais_30', @NombreBK;
        PRINT '>>> BACKUP GENERADO: ' + @NombreBK;
    END
    ELSE
    BEGIN
        PRINT '>>> BACKUP EXISTENTE: ' + @NombreBK + ' (Se omite nuevo respaldo)';
        DROP PROCEDURE [dbo].[spct_reproceso_resumen_by_pais_30];
    END
END
GO
CREATE PROCEDURE [dbo].[spct_reproceso_resumen_by_pais_30]                   
AS  
BEGIN
	BEGIN TRY
	DECLARE @inicio_proceso DATETIME = GETDATE(),
	        @NombreSP VARCHAR(200) = 'spct_reproceso_resumen_by_pais_30';

	-- Establece la fecha de inicio del procesamiento (hoy)
	declare  @fechaFin date = DATEADD(DAY, -5, getdate());   
	declare @fechaFinLimite date = DATEADD(DAY, -60, @fechaFin); 

	exec spct_reproceso_resumen_by_pais_hosting null, null, @fechaFin, @fechaFinLimite

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
			@extra_info = '{"Error": "Error en reproceso resumen 30"}';

		THROW;
	END CATCH
end 



