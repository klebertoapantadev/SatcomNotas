CREATE   PROCEDURE spct_mon_not_desconexion_fiscal
as
BEGIN
    IF OBJECT_ID('tempdb..#Pendientes') IS NOT NULL DROP TABLE #Pendientes;

    SELECT 
        co_id_comprobante AS IdComprobante,
        co_hora_in AS HoraIn,
        co_pais as Pais,
		co_detalle as Mensaje,
		DescripcionEstatus,
		co_nemonico as Nemonico,
		co_estatus,
		co_numero_reprocesos
    into #Pendientes
    FROM sat_comprobante.dbo.com_log_comprobante_xml with (nolock)	
	inner join sat_catalogo..sc_vista_estados_documentos  on co_estatus = CodigoEstatus
    where co_id_comprobante>0
	and co_hora_in >= DATEADD( day, -1, getdate())
	and Autorizado = 0 	
	and (co_estatus in(51,53,55,56)  ---estados 
	or (co_detalle like '%The SSL%' or co_detalle like '%SSL/TLS%') or co_detalle like '%sending%'or co_detalle like '%GenericJDBCException%');
	--| Error 1):  An error occurred while sending the request. Error 2):  An error occurred while sending the request. Error 3):  Unable to read data from the transport connection: An existing connection was forcibly closed by the remote host.. Error 4):  An existing connection was forcibly closed by the remote host.   |
	-- | Error 1):  org.hibernate.exception.GenericJDBCException: Could not open connection   |

	
    
	DECLARE @ResultadoErrores VARCHAR(MAX);

	-- 1. Obtenemos los errores (usando tu lógica anterior)
	WITH ErroresCTE AS (
		SELECT DISTINCT top 3 LTRIM(RTRIM(REPLACE(Split.value, '.', ''))) AS ErrorLimpio
		FROM (
			SELECT CAST('<m>' + REPLACE(REPLACE(REPLACE(REPLACE(Mensaje, 'Error 1):', '</m><m>'), 'Error 2):', '</m><m>'), 'Error 3):', '</m><m>'), 'Error 4):', '</m><m>') + '</m>' AS XML) AS XmlData 
			FROM #Pendientes
		) AS Base
		CROSS APPLY (SELECT r.value('.', 'VARCHAR(MAX)') as value FROM XmlData.nodes('/m') as t(r)) AS Split
		WHERE LTRIM(RTRIM(Split.value)) <> '' AND LTRIM(RTRIM(Split.value)) NOT LIKE 'Mensaje%'
	)
	SELECT @ResultadoErrores = STRING_AGG(ErrorLimpio, ' | ') FROM ErroresCTE;

	-- 2. LIMPIEZA CRÍTICA: Eliminar saltos de línea y tabulaciones que rompen OLE DB
	SET @ResultadoErrores = REPLACE(@ResultadoErrores, CHAR(13), ''); -- Carriage Return
	SET @ResultadoErrores = REPLACE(@ResultadoErrores, CHAR(10), ''); -- Line Feed
	SET @ResultadoErrores = REPLACE(@ResultadoErrores, CHAR(9), '');  -- Tab
	-- Eliminar el caracter de "pipe" extra que mostraste en tu ejemplo o comillas dobles
	SET @ResultadoErrores = REPLACE(@ResultadoErrores, '"', ''''); 
	SET @ResultadoErrores = REPLACE(@ResultadoErrores, '|', '-');

	-- 3. Construir el JSON final asegurando el tipo de dato
	DECLARE @JsonFinal VARCHAR(MAX);
	SET @JsonFinal = '{"Mensaje": "' + ISNULL(substring( @ResultadoErrores,0,200), 'Sin error detallado') + '"}';



	--select @JsonFinal =  '{}'--
	-- Ver resultado
	SELECT @JsonFinal AS MensajeFinal;

    DECLARE @PaisActual INT;
    DECLARE @Mensaje NVARCHAR(MAX);

    DECLARE cursor_paises CURSOR FOR 
    SELECT DISTINCT Pais FROM #Pendientes;

    OPEN cursor_paises;
    FETCH NEXT FROM cursor_paises INTO @PaisActual;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Mensaje = 'Detalles Desconexión:' + CHAR(13) + CHAR(10);

        -- Procesamos cada hora y sus IDs asociados en una sola cadena
        -- Usamos STRING_AGG para los IDs dentro de cada grupo de hora
        SELECT @Mensaje = @Mensaje + 
            '#' + RIGHT('000' + CAST(COUNT(1) AS VARCHAR(5)), 3) + 
            ' : ' + FORMAT(HoraIn, 'MMMdd HH:00') + 
            ' Detalle: ' + (
                SELECT STRING_AGG(CAST(IdComprobante AS VARCHAR(50)), ' ')
                FROM (
                    -- Limitamos a los IDs que pertenecen exactamente a esta hora y país
                    SELECT TOP 10 IdComprobante 
                    FROM #Pendientes innerSub 
                    WHERE innerSub.Pais = @PaisActual 
                    AND FORMAT(innerSub.HoraIn, 'MMMdd HH:00') = FORMAT(outerSub.HoraIn, 'MMMdd HH:00')					 
                ) t
            ) + CHAR(13) + CHAR(10)
        FROM #Pendientes outerSub
        WHERE Pais = @PaisActual
        GROUP BY FORMAT(HoraIn, 'MMMdd HH:00')
        ORDER BY FORMAT(HoraIn, 'MMMdd HH:00') ASC;


		print concat( @PaisActual,' ::' ,@Mensaje  )

		
        -- Enviar a la bitácora/alerta
        EXEC [master].[dbo].[spct_insertar_alerta_postgres]
            @severity = 'Alerta',
            @process = 'Desconexión Autorizador (helpdesk)',
            @country = @PaisActual,
            @issuing = '-',   
            @message = @Mensaje,
			@extra_info = @JsonFinal;

        
        FETCH NEXT FROM cursor_paises INTO @PaisActual;
    END

    CLOSE cursor_paises;
    DEALLOCATE cursor_paises;
END



