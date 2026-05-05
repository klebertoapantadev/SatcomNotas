Text
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('[dbo].[spct_reproceso_resumen_by_pais_hosting]') IS NOT NULL
BEGIN
    DECLARE @NombreBK NVARCHAR(255) = 'spct_reproceso_resumen_by_pais_hosting_BK_' + REPLACE(CONVERT(VARCHAR, GETDATE(), 106), ' ', '_');
    IF OBJECT_ID(@NombreBK) IS NULL 
    BEGIN
        EXEC sp_rename 'spct_reproceso_resumen_by_pais_hosting', @NombreBK;
        PRINT '>>> BACKUP GENERADO: ' + @NombreBK;
    END
    ELSE
    BEGIN
        PRINT '>>> BACKUP EXISTENTE: ' + @NombreBK + ' (Se omite nuevo respaldo)';
        DROP PROCEDURE [dbo].[spct_reproceso_resumen_by_pais_hosting];
    END
END
GO
CREATE  PROCEDURE [dbo].[spct_reproceso_resumen_by_pais_hosting]                     
@pais int = null   
,@borrar bit = 0 
,@fechaFin date = null  
,@fechaInicio date = null  
AS           
 
 --if(@fechaFin is null and @fechaInicio is null) return 0;  
 --------------------------------------------------------- 
 ------Definimos el límite de tiempo 
 --DECLARE @FechaLimite DATETIME = '20251224 14:00:00'; -- Comprobamos si la hora actual es anterior al límite 
 --IF GETDATE() < @FechaLimite BEGIN -- Imprime un mensaje opcional para el log de ejecución 
 --PRINT 'Es antes de las 14:00. Iniciando espera de 2 horas...'; -- Pausa la ejecución por 02 horas, 00 minutos y 00 segundos
 --WAITFOR DELAY '02:00:00'; PRINT 'Espera finalizada. Continuando proceso.'; 
 --END
 -------------------------------------------------------
 --select * from  sat_comprobante.dbo.com_control_ejecucion  
 declare   @params varchar(max),@inicio datetime = getdate(),@fin datetime , @sp varchar(100) = DB_NAME()+'.dbo.'+OBJECT_NAME(@@PROCID), @procesados int = 0;  
   
   
--select @@servername    
              
-- sp_recompile spct_reproceso_resumen_by_pais                
Begin    
  
  
 if exists(SELECT *  FROM com_control_ejecucion  where FechaInicio > dateadd(MINUTE,-10, getdate())                 
 and Procedimiento = @sp )                
 begin                
	print 'Ya se encuentra en ejecucion '+ @sp                  
	SELECT *  FROM com_control_ejecucion  where FechaInicio > dateadd(MINUTE,-10, getdate())                 
	and Procedimiento = @sp 
	return 0                
 end                
 --Inserta control                
 INSERT INTO sat_comprobante.dbo.com_control_ejecucion (Procedimiento, FechaInicio, Usuario)                
 VALUES (@sp, GETDATE(), SYSTEM_USER);                
   
  
  
  --Inicio try                
  BEGIN TRY
  set transaction isolation level read uncommitted                  
  
-- ********************************************************  
-- Parámetros de Configuración  
-- ********************************************************  
DECLARE @DiasMonitoreo INT = 5; -- Número de días hacia atrás a monitorear (incluyendo hoy)  
DECLARE @fechaFinLimite DATE;       -- La fecha más antigua a la que debemos llegar  
DECLARE @fechaFinActual DATE;       -- La fecha que se procesa en la iteración  
  
if(@@servername = 'EC2AMAZ-IVL1JSC') select @pais = 57;  --Control colombia  
  
-- ********************************************************  
-- Configuración del Rango  
-- ********************************************************  
  
-- Establece la fecha de inicio del procesamiento (hoy)  
if(@fechaFin is null)  
 SET @fechaFinActual = CAST(GETDATE() AS DATE);   
else  
 SET @fechaFinActual= @fechaFin   
  
-- Establece la fecha límite (ej. hoy - 20 días)  
if(@fechaInicio is null)  
 SET @fechaFinLimite = DATEADD(DAY, -@DiasMonitoreo, @fechaFinActual);  
else  
 SET @fechaFinLimite = @fechaInicio  
  
-- ********************************************************  
-- Bucle de Ejecución  
-- ********************************************************  
select @fechaFinActual, @fechaFinLimite  
  
WHILE @fechaFinActual >= @fechaFinLimite  
BEGIN  
  
   
    -- Muestra la fecha que se está procesando  
    PRINT 'Ejecutando SP para la fecha: ' + CONVERT(VARCHAR(10), @fechaFinActual, 120);  
  
    -- Ejecuta el Stored Procedure  
    EXEC [spco_sop_mon_poblar_info_reportes_2025] @pais, NULL, @fechaFinActual, @borrar; 
	exec spco_sop_mon_genera_campos_reporte @fechaFinActual
	--sp_helptext [spco_sop_mon_poblar_info_reportes_2025]  
	--EXEC [spco_sop_mon_poblar_info_reportes_2025] 57, NULL, '2025/11/15';  
  
  
	select   @procesados= count(1),@fin = getdate() FROM com_comprobante_aux  
   
	select @params = '#'+.dbo.fn_get_text(@procesados) + ': '  
	+ 'spco_sop_mon_poblar_info_reportes_2025'  
	+ ' @pais= '+.dbo.fn_get_text(@pais) 
	+ ',@id_emisor: '+.dbo.fn_get_text('0')    
	+ ',@fechaFinActual: '+.dbo.fn_get_text(@fechaFinActual)   
	+ ',@borrar: '+.dbo.fn_get_text(@borrar)   
  
	exec spco_crear_log_consulta @sp,null,'batch',0,@params,'proc_continuo',@inicio,@fin,null,null  
  
    -- Decrementa la fecha en 1 día para pasar al día anterior  
    SET @fechaFinActual = DATEADD(DAY, -1, @fechaFinActual);  
	SET @inicio= getdate();  
   
END  
  
	PRINT 'Proceso de poblamiento finalizado para los últimos ' + CAST(@DiasMonitoreo AS VARCHAR) + ' días.';  
    
    -- Log de éxito global final
    DECLARE @fin_log DATETIME = GETDATE();
    EXEC [dbo].[spco_crear_log_consulta] 
        @i_lc_nombre_sp = @sp,
        @i_lc_emisor = 0,
        @i_lc_parametros = @params, -- Últimos parámetros usados
        @i_lc_origen = 'proc_continuo',
        @i_lc_inicio = @inicio,
        @i_lc_fin = @fin_log;
            
  --fin try                
  END TRY                
  BEGIN CATCH                
     DECLARE @ErrorMessage NVARCHAR(MAX) = ERROR_MESSAGE();
     DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
     DECLARE @ErrorState INT = ERROR_STATE();

     -- Log de error en auditoría
     DECLARE @fin_error DATETIME = GETDATE();
     EXEC [dbo].[spco_crear_log_consulta] 
         @i_lc_nombre_sp = @sp,
         @i_lc_emisor = 0,
         @i_lc_parametros = @params,
         @i_lc_origen = 'proc_continuo',
         @i_lc_inicio = @inicio,
         @i_lc_fin = @fin_error,
         @i_lc_error = @ErrorMessage;

     -- Enviar alerta a Postgres
     EXEC [master].[dbo].[spct_insertar_alerta_postgres]
         @severity = 'Error',
         @process = 'spct_reproceso_resumen_by_pais_hosting',
         @country = @pais,
         @issuing = '-',
         @message = @ErrorMessage,
         @extra_info = '{"Error": "Error en reproceso resumen hosting"}';

     -- Elimina control antes de relanzar el error
     DELETE FROM sat_comprobante.dbo.com_control_ejecucion WHERE Procedimiento = @sp;

     RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
  END CATCH                
  
 --WAITFOR DELAY '00:03:00';                    
 --Elimina control                
 print 'Elimina el control de ejecucion '+ @sp               
 DELETE FROM sat_comprobante.dbo.com_control_ejecucion WHERE Procedimiento = @sp;   
 select * from  sat_comprobante.dbo.com_control_ejecucion  
 return 0                
end   





Completion time: 2026-05-04T10:24:50.0799209-05:00
