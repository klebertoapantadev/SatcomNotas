Text
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

create   proc [dbo].[spco_sop_mon_consultas_recurrentes]
@Fecha date = null
,@Emisor int = null
,@SP varchar(100) =null
as

--[spco_sop_mon_consultas_recurrentes] '2025/12/15', null, null

if(@Fecha is null) select @Fecha= getdate()

----- ordenado por hora -----
/*
select 
em_nombre
,em_nemonico 
,em_pais
,lc_id
,lc_hora_registro
,lc_nombre_sp
,lc_hostname
,lc_appname
,lc_emisor
,lc_parametros
,lc_origen
,DATEDIFF(ms,lc_inicio,lc_fin) as [lc_tiempo(ms)]
,DATEDIFF(ss,lc_inicio,lc_fin) as [lc_tiempo(s)]
,lc_inicio
,lc_fin
,lc_error
,lc_usuario
from sat_logging.dbo.com_log_consultas_bdd with(nolock)
left join sat_catalogo.dbo.sc_emisor  on lc_emisor = em_id_emisor
where lc_hora_registro >= @Fecha
and (@Emisor  is null or lc_emisor =@Emisor ) 
order by lc_hora_registro desc



*/
if(@Emisor is not null and @SP is null)
begin
	
	select 
	count(1) as NumConsultas
	,em_nombre
	,em_nemonico 
	,em_pais
	,lc_nombre_sp
	,lc_emisor
	,dbo.fn_get_scrip_sp(lc_parametros)
	,lc_usuario
	from sat_logging.dbo.com_log_consultas_bdd with(nolock)
	left join sat_catalogo.dbo.sc_emisor  on lc_emisor = em_id_emisor
	where convert(date,lc_hora_registro) = @Fecha
	and lc_emisor =@Emisor 
	--and (@SP is null or @SP = lc_nombre_sp )
	group by em_nombre
	,em_nemonico 
	,em_pais
	,lc_nombre_sp
	,lc_emisor
	,lc_parametros
	,lc_usuario
	having count(1)> 3
	order by NumConsultas desc
end
else if(@Emisor is  null and @SP is not null)
begin
	
	select 
	count(1) as NumConsultas
	,em_nombre
	,em_nemonico 
	,em_pais	
	,lc_nombre_sp
	,lc_emisor
	--,dbo.fn_get_scrip_sp(lc_parametros)
	,lc_parametros
	,lc_usuario
	from sat_logging.dbo.com_log_consultas_bdd with(nolock)
	left join sat_catalogo.dbo.sc_emisor  on lc_emisor = em_id_emisor
	where convert(date,lc_hora_registro) = @Fecha
	--and lc_emisor =@Emisor 
	and lc_nombre_sp like '%'+ @SP+'%'
	group by em_nombre
	,em_nemonico 
	,em_pais
	,lc_nombre_sp
	,lc_emisor
	,lc_parametros
	,lc_usuario
	having count(1)> 3
	order by NumConsultas desc

	select datediff( SECOND,  lc_inicio, lc_fin) as [Tiempo (s)], *
	from sat_logging.dbo.com_log_consultas_bdd with(nolock)
	where convert(date,lc_hora_registro) = @Fecha	
	and lc_nombre_sp = @SP
	order by lc_hora_registro desc
	
end
else 
begin
	
	select 
	count(1) as NumConsultas
	,em_nombre
	,em_nemonico 
	,em_pais
	,lc_nombre_sp
	,lc_emisor
	--,dbo.fn_get_scrip_sp(lc_parametros)
	,lc_parametros
	,lc_usuario
	from sat_logging.dbo.com_log_consultas_bdd with(nolock)
	left join sat_catalogo.dbo.sc_emisor  on lc_emisor = em_id_emisor
	where convert(date,lc_hora_registro) = @Fecha
	group by em_nombre
	,em_nemonico 
	,em_pais
	,lc_nombre_sp
	,lc_emisor
	,lc_parametros
	,lc_usuario
	having count(1)> 3
	order by NumConsultas desc


	select datediff( MILLISECOND,  lc_inicio, lc_fin) as [Tiempo (ms)], *
	from sat_logging.dbo.com_log_consultas_bdd with(nolock)
	where convert(date,lc_hora_registro) = @Fecha		
	order by [Tiempo (ms)] desc
end

