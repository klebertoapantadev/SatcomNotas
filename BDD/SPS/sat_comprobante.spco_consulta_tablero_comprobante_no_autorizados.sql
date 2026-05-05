create or alter    PROCEDURE [dbo].[spco_consulta_tablero_comprobante_no_autorizados]
@i_IdEmisor varchar(max) =null

--spco_consulta_tablero_comprobante_no_autorizados 517
AS
BEGIN
    SET NOCOUNT ON;
	

    DECLARE @i_dias_actual INT = 5;
    DECLARE @i_dias_hist INT = 15;
    DECLARE @aux_ambiente VARCHAR(50), @aux_ambiente2 VARCHAR(50);

    -- 1. Obtener ambiente una sola vez
    EXEC sat_catalogo.dbo.sp_get_valor_variable_app 'sql_ambiente', @aux_ambiente OUT, @aux_ambiente2 OUT, @@SERVERNAME;

    -- 2. Consolidar registros de tablas actuales e históricas en una sola carga
    SELECT  
        @aux_ambiente AS ambiente, 
        co_id_emisor, co_id_comprobante, co_hora_in, co_fecha_emision, co_estatus, 
        co_num_comprobante, co_codigo_tipo_documento, CAST(co_detalle AS VARCHAR(MAX)) AS co_detalle,
        co_establecimiento, co_punto_emision, CAST(0 AS BIT) AS co_info_detalles, 
        CAST('' AS VARCHAR(500)) AS co_motivo, co_pais, cast(0 as bit) as Reprocesable
    INTO #resultNoAutorizados
    FROM (
        SELECT co_id_emisor, co_id_comprobante, co_hora_in, co_fecha_emision, co_estatus, 
        co_num_comprobante, co_codigo_tipo_documento, CAST(co_detalle AS VARCHAR(MAX)) AS co_detalle,
        co_establecimiento, co_punto_emision, co_pais
		FROM sat_comprobante..com_log_comprobante_xml WITH(NOLOCK) inner join sat_catalogo..sc_vista_estados_documentos on CodigoEstatus = co_estatus
        WHERE co_hora_in > DATEADD(DAY, -@i_dias_actual, CAST(GETDATE() AS DATE)) AND co_estatus <> 14 AND Autorizado = 0
		and (@i_IdEmisor is null or co_id_emisor=  @i_IdEmisor)
        --UNION ALL
        --SELECT * FROM sat_comprobante_historica..com_log_comprobante_xml WITH(NOLOCK) inner join sat_catalogo..sc_vista_estados_documentos on CodigoEstatus = co_estatus
        --WHERE co_hora_in > DATEADD(DAY, -@i_dias_hist, CAST(GETDATE() AS DATE)) AND co_estatus <> 14 AND Autorizado = 0
    ) AS log_union
    INNER JOIN sat_catalogo..sc_vista_tipo_documetos ON CodigoNegocio = co_codigo_tipo_documento AND co_pais = Pais
    INNER JOIN sat_catalogo..sc_vista_estados_documentos  v ON v.CodigoEstatus = co_estatus;

    -- 3. Obtener y agregar detalles filtrando mensajes ruidosos
    -- Usamos una CTE para limpiar el log antes de agrupar
    WITH DetalleLimpio AS (
        SELECT dl_id_comprobante, dl_mensaje
        FROM sat_comprobante.dbo.com_detalle_log WITH(NOLOCK)
        WHERE dl_id_comprobante IN (SELECT co_id_comprobante FROM #resultNoAutorizados WHERE co_detalle IS NULL)
          AND dl_evento NOT IN (11, 28, 3, 30)
          AND NOT EXISTS (
              SELECT 1 FROM (VALUES 
                ('Fin proceso'), ('Consulte el detalle'), ('Envio BDD online.'), ('spflip'), 
                ('EstadoAutorizador sin homologacion'), ('Envio colas DBB'), ('EnvioTramaOffApiCliente'), 
                ('Genera clave'), ('Tiempo Proceso'), ('Homologa pais:'), ('Homologa SAT:'), 
                ('Fecha de emisión original'), ('[procesando]'), ('[rechazado]'), ('Sec. entregado'), 
                ('[Valida DTO]'), ('ReProcesarTramaIn'), ('comprobante se encuentra en proceso'), 
                ('[Actualiza comprobante]'), ('[Homologa:'), ('[No tiene impresora]'), 
                ('[Proceso de LogMySatcom]'), ('[Comprobante autorizado]'), ('[Sig:'), 
                ('EnProcesamientoAut'), ('Diferencia en emisión'), ('ErrorEnvioAutorizador')
              ) AS Exclusiones(Patron)
              WHERE dl_mensaje LIKE '%' + Patron + '%'
          )
    )


    UPDATE NA
    SET co_detalle = DET.MensajesMultilinea,
        co_info_detalles = 1
    FROM #resultNoAutorizados AS NA 
    INNER JOIN (
        SELECT dl_id_comprobante, STRING_AGG(dl_mensaje, CHAR(13) + CHAR(10)) AS MensajesMultilinea
        FROM DetalleLimpio
        GROUP BY dl_id_comprobante
    ) AS DET ON DET.dl_id_comprobante = NA.co_id_comprobante;

    -- 4. Clasificación de Motivos y Limpieza en un solo paso (Evita 12+ UPDATES)
	--'homologa errores'
	

    UPDATE #resultNoAutorizados
    SET co_detalle = REPLACE(co_detalle, 'El archivo XML,fue enviado a la Dirección General de Tributación de manera extemporánea; con base en lo estipulado en el artículo 9 y 15 ambos de la resolución 48-2016', '??'),
        co_motivo = ISNULL(STUFF(
            (SELECT '|' + Motivo
             FROM (
SELECT 'Actividad Economica Emisor' AS Motivo WHERE co_detalle LIKE '%El Código de la Actividad Económica del emisor%'
                UNION ALL SELECT 'Actividad Economica Receptor' WHERE co_detalle LIKE '%El Código de la Actividad Económica del receptor%'
					or co_detalle LIKE '%AnonType_CodigoActividadReceptor%'						
                UNION ALL SELECT 'Teléfono Receptor' WHERE co_detalle LIKE '%dTfnRec'' element is invalid%' 
				UNION ALL SELECT 'Datos Receptor' WHERE co_detalle LIKE '%dNombRec'' element is invalid%' 
					or co_detalle like '%gDatRec''%invalid%dTfnRec%'
					or co_detalle like '%iTipoRec%element is invalid%'
					or co_detalle like '%dDirecRec%element is invalid%'
					or co_detalle like '%cPaisRec%element is invalid%'
				UNION ALL SELECT 'identificación Receptor' WHERE co_detalle LIKE '%La identificación del Receptor no coincide%' 
					or co_detalle LIKE '%Número de cédula%estructura establecida%'
					or co_detalle like '%La identificación del Receptor no coincide con la del Receptor del documento original%'
					or co_detalle like '%identificación del receptor no corresponde a un registro válido%'
					or co_detalle like '%ERROR EN LA IDENTIFICACION DEL RECEPTOR%'
					or co_detalle like '%RUC del receptor contribuyente impedido de facturar%'
					or co_detalle like '%RUC del receptor no es de gobierno%'
					or co_detalle like '%existente con tipo de receptor consumidor final%'
					or co_detalle like '%receptor de la FE debe ser Panamá si el destino de la operación es Panamá%'					
                UNION ALL SELECT 'Digito Verificador Incorrecto' WHERE co_detalle LIKE '%El DV del NIT no es correcto%'
					or co_detalle like '%dDV'' element is invalid - The value%'
				UNION ALL SELECT 'Fecha Incorrecta' WHERE co_detalle LIKE '%La fecha en la clave%no puede ser superior%'
				UNION ALL SELECT 'Identificación Incorrecta' WHERE co_detalle like '%Ruc%element is invalid%'
				UNION ALL SELECT 'Información del producto' WHERE co_detalle like '%List of possible elements expected%gCodItem%gITBMSItem%'
				UNION ALL SELECT 'Configuracion Incorrecta' WHERE co_detalle LIKE '%Falta configuración de secuenciales%'	
					or co_detalle like '%Establecimiento/Punto no configurado%'
                UNION ALL SELECT 'Descuadre Valores' WHERE co_detalle LIKE '%El monto total%no coincide%' 
					or co_detalle like '%El resumen de la factura carece del monto Total No Sujeto y cuenta con servicios o mercancías No sujetas de IVA%' 
					or co_detalle like '%no corresponde a la sumatoria de los impuestos calculados a productos%'
					or co_detalle like '%no corresponde al valor de multiplicar el monto total por la tarifa del impuesto%'
					or co_detalle like '%ERROR EN DIFERENCIAS%'
					or co_detalle like '%Suma total de monto gravado invalida%'	
					or co_detalle like '%Valor total de la factura inválido%'
					or co_detalle like '%Valor total de los ítems inválidos%'
					or co_detalle like '%Suma de los precios antes de impuesto invalida%'
					or co_detalle like '%Monto del ITBMS del ítem inválido%'
					or co_detalle like '%Monto del ITBMS del ítem inválido%'
					or co_detalle like '%Precio del ítem inválido%'
					or co_detalle like '%dValTotItem'' element is invalid%'
					or co_detalle like '%dPrUnit'' element is invalid%'
					or co_detalle like '%dPrUnit%element is invalid%'
					or co_detalle like '%dPrItem%element is invalid%'
					or co_detalle like '%dValTotItem%element is invalid%'
					or co_detalle like '%dVTot%element is invalid%'
					or co_detalle like '%dVTotItems%element is invalid%'
					or co_detalle like '%dValITBMS%element is invalid%'
					or co_detalle like '%dTotDesc%element is invalid%'
					or co_detalle like '%dTotDesc%element is invalid%'
					or co_detalle like '%dDescProd%element is invalid%'
				UNION ALL SELECT 'Valor Impuesto' WHERE co_detalle LIKE '%El valor del tributo informado no corresponde al producto del porcentaje%'					
					or co_detalle like '%Falta los impuestos del producto%'
                UNION ALL SELECT 'Valores Negativos' WHERE co_detalle LIKE '%cvc-minInclusive-valid%'
				UNION ALL SELECT 'Error en Firmado' WHERE co_detalle LIKE '%Valor de la firma diferente del calculado por la aplicación de la DIRECCIÓN GENERAL DE INGRESOS%'
                UNION ALL SELECT 'Sin datos del cliente' WHERE co_detalle LIKE '%No se cuenta con información del cliente%'
                UNION ALL SELECT 'Error al generar TOKEN' WHERE co_detalle LIKE '%Error al generar TOKEN%'				
				UNION ALL SELECT 'SIN CABYS' WHERE co_detalle LIKE '%no tiene código CABY%'
				UNION ALL SELECT 'Precio Cero' WHERE co_detalle LIKE '%El precio unitario de la línea % debe ser mayor a cero%'				
				UNION ALL SELECT 'SIN DETALLES' WHERE co_detalle LIKE '%El documento debe contener Detalle de Sevicios u Otros Cargos%'
					or co_detalle like '%El comprobante no tiene detalles%'
					or co_detalle like '%El documento no tiene detalles%'
                UNION ALL SELECT 'CABYS incorrecto' WHERE co_detalle LIKE '%no se encuentra en el Catálogo%CAByS%' 
							or co_detalle like '%AnonType_CodigoCABYSLineaDetalleDetalleServicioTiqueteElectronico%'
                UNION ALL SELECT 'Telefono Cliente' WHERE co_detalle LIKE '%AnonType_NumTelefonoTelefonoType%'
    UNION ALL SELECT 'Consecutivo ya utilizado' WHERE co_detalle LIKE '%La numeración consecutiva%' AND co_detalle LIKE '%ya existe%'
				UNION ALL SELECT 'Condicion Venta OTRO' WHERE co_detalle LIKE '%El campo denominado ''Detalle Condicion de la Venta OTRO'' no posee la estructura establecida para el mismo%'
				UNION ALL SELECT 'Codigo Descuento OTRO' WHERE co_detalle LIKE '%El ''Codigo Descuento Otro'' es obligatorio cuando se utilice el Codigo Descuento ''99'' en la línea%'
				UNION ALL SELECT 'Digest Value' WHERE co_detalle LIKE '%Error obteniendo Digest Value%'			
				UNION ALL SELECT 'Exoneraciones' WHERE co_detalle LIKE '%ExoneracionType%'
					or co_detalle like '%En la línea % se seleccionó el Nombre Institución 99%'
					or co_detalle like '%documento de exoneración indicado,no se encuentra registrado%' 
				UNION ALL SELECT 'Direccion incorrecta' WHERE co_detalle LIKE '%BarrioUbicacionType%'	
					or co_detalle LIKE '%OtrasSenasType%'
					or co_detalle like '%CantonUbicacionType%'
					or co_detalle like '%Distrito donde se ubica el receptor contribuyente no existe%'
					or co_detalle like '%Dirección del receptor contribuyente no informada%'
					or co_detalle like '%dCodUbi'' element is invalid%'
				UNION ALL SELECT 'Codigo Medio Pago OTRO' WHERE co_detalle LIKE '%El Tipo Medio Pago OTRO es obligatorio cuando se utilice el Tipo de Medio Pago%'
				UNION ALL SELECT 'Codigo Descuento' WHERE co_detalle LIKE '%CodigoDescuento}'' is expected%'
				UNION ALL SELECT 'Codigo Moneda' WHERE co_detalle LIKE '%CodigoTipoMoneda}'' is expected%'
				UNION ALL SELECT 'Version Documento' WHERE co_detalle LIKE '%El tipo de documento o la versión del comprobante enviado no es soportado%'
				UNION ALL SELECT 'mySatcom' WHERE co_detalle LIKE '%One or more errors occurred. (A task was canceled.)%'
				or co_detalle like '%Collection was modified; enumeration operation may not execute%'
				UNION ALL SELECT 'Error no controlado' WHERE co_detalle LIKE '%Object reference not set to an instance of an object%'				
				UNION ALL SELECT 'CUFE mal calculado' WHERE co_detalle LIKE '%Valor del CUFE no está calculado correctamente%'								
				UNION ALL SELECT 'CUFE mal formado' WHERE co_detalle LIKE '%CUFE malformado%'
					or co_detalle like '%The value ''FE% is invalid according to its datatype ''String''%'
				UNION ALL SELECT 'CUFE Referencia' WHERE co_detalle LIKE '%dCUFERef%element is invalid%'
				UNION ALL SELECT 'Validación de Esquema' where co_detalle like '%Error en validación de esquema: Root element is missing%'
					or co_detalle like '%Error en validación de esquema%'
				UNION ALL SELECT 'Formas de Pago' WHERE co_detalle LIKE '%El monto total del comprobante no coincide con la suma de los totales por medios de pago%'
					or co_detalle like '%Cuando se utilice más de un medio de pago,el campo Monto Total por Medio de Pago es obligatorio%'
					or co_detalle like '%Las formas de pago son obligatorias%'
					or co_detalle like '%Falta la descripción de forma de pago%'
					or co_detalle like '%Medio de pago informado es invalido%'
					or co_detalle like '%FormaPago'' element is invalid - The value%'
					or co_detalle like '%dFormaPagoDesc%element is invalid%'
				UNION ALL SELECT 'Documentos Asociados NC/ND' WHERE co_detalle LIKE '%Se requiere definir los documentos asociados para NC/ND%'
					or co_detalle like '%con el mismo receptor en la nota de crédito/débito%'
					or co_detalle like '%Documento Fiscal Referenciado posterior a la emisión%'
					or co_detalle like '%The element ''gDFRefNum'' in namespace%'
					--
				UNION ALL SELECT 'Email Inválido' WHERE co_detalle LIKE '%dCorElectRec'' element is invalid%'
				UNION ALL SELECT 'Código de Producto' WHERE co_detalle LIKE '%No informado ningún código de producto%'
					or co_detalle like '%No informado código de producto en la Codificación Panameña%'
					or co_detalle like '%dCodCPBSabr%element is invalid%'
					or co_detalle like '%dCodCPBScmp%element is invalid%'
					or co_detalle like '%dCodProd%element is invalid%'					
				UNION ALL SELECT 'Vuelto Inválido' WHERE co_detalle LIKE '%Vuelto entregado al cliente inválido%'
				UNION ALL SELECT 'Ambiente Inválido' WHERE co_detalle LIKE '%Ambiente de destino del mensaje errado%'
				UNION ALL SELECT 'Error en Certificado' WHERE co_detalle LIKE '%No fue posible generar el documento electrónico%'
				UNION ALL SELECT 'Rango Invalido' WHERE co_detalle LIKE '%superior al final del rango de numeración otorgado%'
				UNION ALL SELECT 'Factura EXP incompleta' WHERE co_detalle LIKE '%The element ''gFExp''%has invalid child element ''cMoneda''%'
					or co_detalle like '%dPuertoEmbarq%element is invalid%'				
             ) AS Clasificacion
             FOR XML PATH(''), TYPE).value('.', 'VARCHAR(MAX)'), 1, 1, ''), '')
    WHERE co_detalle IS NOT NULL;

    -- Resultado final

	begin
		UPDATE #resultNoAutorizados
    SET co_detalle = REPLACE(co_detalle, '| Razón rechazo:   <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">    <s:Header xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" />    <soap:Body>      <ns2:autorizacionComprobanteRespon








se xmlns:ns2="http://ec.gob.sri.ws.autorizacion">        <RespuestaAutorizacionComprobante>          ', '??');
	end


	UPDATE #resultNoAutorizados
    SET co_detalle = REPLACE(co_detalle, '<numeroComprobantes>0</numeroComprobantes>          <autorizaciones />        </RespuestaAutorizacionComprobante>      </ns2:autorizacionComprobanteResponse>    </soap:Body>  </soap:Envelope>', '??')

	UPDATE #resultNoAutorizados
    SET co_detalle = REPLACE(co_detalle, '| Razón rechazo: <rRetEnviFe xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://dgi-fep.mef.gob.pa/wsdl/FeRecepFE"><dVerForm>1.00</dVerForm><iAmb>2</iA



mb><dVerApl>1.00</dVerApl><rProtFe><dVerForm>1.00</dVerForm><gInfProt>', '??')

		UPDATE #resultNoAutorizados
    SET co_detalle = REPLACE(co_detalle, '</gInfProt></rProtFe></rRetEnviFe> |', '??')

		UPDATE #resultNoAutorizados
    SET co_detalle = REPLACE(co_detalle, '| Razón rechazo: <rRetEnviFe xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://dgi-fep.mef.gob.pa/wsdl/FeRecepFE"><dVerForm>1.00</dVerForm><iAmb>1</iA



mb><dVerApl>1.00</dVerApl><rProtFe><dVerForm>1.00</dVerForm><gInfProt>', '??')

		UPDATE #resultNoAutorizados
    SET co_detalle = REPLACE(co_detalle, '| Razón rechazo: <rRetEnviFe xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://dgi-fep.mef.gob.pa/wsdl/FeRecepFE"><dVerForm>1.00</dVerForm><iAmb>1</iA



mb><dVerApl>1.00</dVerApl><rProtFe><dVerForm>1.00</dVerForm><gInfProt>', '??')

	UPDATE #resultNoAutorizados
	SET co_detalle = REPLACE(co_detalle, '</gInfProt><Signature /></rProtFe></rRetEnviFe> |', '??')

	--UPDATE #resultNoAutorizados SET co_detalle = REPLACE(co_detalle, 'XXX', '??')


	update #resultNoAutorizados
	set co_motivo = 'CUFE mal formado' 
	where co_motivo like '%CUFE mal formado%'
	
	update #resultNoAutorizados 
	set Reprocesable = 1 
	where co_detalle = 'mySatcom' 

	truncate table co_comprobante_rechazado;   
	
	insert into co_comprobante_rechazado
	SELECT ambiente,
	co_motivo,
	co_pais,
	em_nemonico as co_nemonico,
	co_id_emisor,
	co_id_comprobante,
	cast(co_hora_in as date) as co_hora_in,
	cast(co_fecha_emision as date) as co_fecha_emision,
	co_estatus,
	co_num_comprobante,
	co_codigo_tipo_documento,
	co_establecimiento,
	co_punto_emision,
	Reprocesable,
	co_info_detalles,--Toma la info desde los detalles
	co_detalle,
	getdate() as co_ultima_actualizacion	
	FROM #resultNoAutorizados  
	inner join sat_catalogo..sc_emisor on em_id_emisor = co_id_emisor
	--where co_pais = 506
	--ORDER BY co_motivo DESC;


   select * from co_comprobante_rechazado ORDER BY co_motivo DESC;


   /*
   DECLARE @TableName NVARCHAR(128) = '#Resultado'; -- Pon aquí el nombre de tu tabla

   SELECT 
		'CREATE TABLE MiTablaPermanente (' + 
		STRING_AGG(
			CAST(CHAR(13) + '    ' + COLUMN_NAME + ' ' + DATA_TYPE + 
			CASE 
				WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
				ELSE ''
			END + 
			CASE WHEN IS_NULLABLE = 'NO' THEN ' NOT NULL' ELSE ' NULL' END AS NVARCHAR(MAX)),
		',') + 
		CHAR(13) + ');' AS ScriptDeCreacion
	FROM tempdb.INFORMATION_SCHEMA.COLUMNS
	WHERE TABLE_NAME LIKE @TableName + '%';

   */
	
   	--Para analizar errores--
	
	/*
		SELECT count(1), co_motivo,  co_detalle FROM #resultNoAutorizados
		WHERE co_pais = 507
		--and co_detalle IS NOT NULL
		and co_motivo = 'Digest Value|Validación de Esquema'
		--and nullif(co_motivo,'') is null
		--and co_motivo not in ('Teléfono Receptor|Digest Value|Validación de Esquema','Identificacion Incorrecta|Digest Value|Validación de Esquema'
		--,'Descuadre Valores|Digest Value|Validación de Esquema','Digito Verificador Incorrecto|Identificacion Incorrecta|Digest Value|Validación de Esquema'
		--,'Identificacion Incorrecta|Digest Value|Direccion incorrecta|Validación de Esquema'
		--,'Identificacion Incorrecta|Digest Value|Validación de Esquema|Email Inválido'
		--)
		and co_motivo like '%Digest Value%'
		group by co_detalle , co_motivo
		order by 1 desc, 2

	*/
	/*
		SELECT top 100 * FROM #resultNoAutorizados
		WHERE co_pais = 57
		and co_detalle like '%No fue posible generar el documento electrónico%'	
		order by 1 desc
	*/


END



