CREATE procedure [dbo].[spco_crear_log_consulta]  
@i_lc_nombre_sp varchar(200) = null,
@i_lc_hostname varchar(200) =null,
@i_lc_appname varchar(200) =null,
@i_lc_emisor int =null,
@i_lc_parametros nvarchar(max) =null,
@i_lc_origen varchar(100)= null,
@i_lc_inicio datetime =null,
@i_lc_fin datetime =null,
@i_lc_error nvarchar(max) =null,
@i_lc_usuario varchar(100) = null
as
begin

insert into sat_logging.dbo.com_log_consultas_bdd(
lc_hora_registro,
lc_nombre_sp,
lc_hostname ,
lc_appname ,
lc_emisor ,
lc_parametros ,
lc_origen ,
lc_inicio ,
lc_fin ,
lc_error ,
lc_usuario
)
values
(
getdate(),
@i_lc_nombre_sp ,
@i_lc_hostname ,
@i_lc_appname ,
@i_lc_emisor ,
@i_lc_parametros ,
@i_lc_origen ,
@i_lc_inicio ,
@i_lc_fin,
@i_lc_error,
@i_lc_usuario  
)

--spco_crear_log_consulta 'sp_prueba',null,'batch',1,'sdfsfdf','BDD','2023-01-01','2023-01-01',null

end

