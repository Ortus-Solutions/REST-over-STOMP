component accessors=true  {
    property name='RequestService' inject='coldbox:RequestService';
    property name='FRTransService' inject='FRTransService@REST-over-STOMP';
    property name='controller' inject='coldbox';
    property name='settings' inject='coldbox:modulesettings:REST-over-STOMP';
    property name='log' inject='logbox:logger:{this}';

    function processRequest( 
		string route        = "",
		string event        = "",
		struct params       = {},
		struct headers      = {},
		string method       = "GET",
        string queryString  = "",
        string domain       = ""
     ) {
        

		try {
            var = FRTransaction = FRTransService.startTransaction(
                'REST over Stomp',
                generateSource( argumentCollection = arguments ),
                // struct of properties
                {
                    'route': arguments.route,
                    'event': arguments.event,
                    'method': arguments.method,
                    'queryString': arguments.queryString,
                    'domain': arguments.domain,
                // Explode and append params as param.name
                }.append( params.reduce( (acc,k,v)=>{
                    acc[ 'params.#k#' ] = v;
                    return acc;
                // Explode and append headers as header.name
                }, {} ) ).append( headers.reduce( (acc,k,v)=>{
                    acc[ 'headers.#k#' ] = v;
                    return acc;
                }, {} ) )
            );

            var handlerResults  = "";
            var requestContext  = getRequestContext();
            var cbController    = getController();
            var requestService 	= cbController.getRequestService();
            var routingService 	= cbController.getRoutingService();
            var renderData      = "";
            var renderedContent = "";
            var iData           = {};


            // add the query string parameters to the request context
            requestContext.collectionAppend( parseQueryString( arguments.queryString ) );        
            // Append in any incoming rc vars. Any querystring on the route will be added later (/index/main?foo=bar)
            requestContext.collectionAppend( params );

            // Allow for our mocked headers to be picked up
            requestContext
                .setPrivateValue( 'mockHTTPRequestHeaders', headers )
                .setPrivateValue( 'mockHTTPMethod', method )
                .setPrivateValue( 'mockStatusCode', 200 )
                .setPrivateValue( 'mockHTTPResponseHeaders', {} );
            
            requestContext.$mixer = $mixer;
            requestContext.$mixer( 'getHTTPHeader', getHTTPHeader );
            requestContext.$mixer( 'getHTTPMethod', getHTTPMethod );
            requestContext.$mixer( 'setHTTPHeader', setHTTPHeader );

            var thisEvent = arguments.event;
			// If the route is for the home page, use the default event in the config/ColdBox.cfc
			if ( arguments.route == "/" ) {
				thisEvent = getController().getSetting( "defaultEvent" );
				requestContext.setValue( requestContext.getEventName(), thisEvent );

                // Prepare all mocking data for simulating routing request
                prepareRoutingService( routingService );
                request.mockCGI = duplicate( cgi );
                request.mockCGI.path_info = arguments.route;
                request.mockCGI.script_name = "";
                request.mockCGI.domain = arguments.domain;

				// Capture the route request
				controller.getRequestService().requestCapture();
			}
			// if we were passed a route, parse it and prepare the SES interceptor for routing.
			else if ( arguments.route.len() ) {
				// separate the route into the route and the query string
				var routeParts = explodeRoute( arguments.route );
				// add the query string parameters from the route to the request context
				requestContext.collectionAppend( routeParts.queryStringCollection );

                // Prepare all mocking data for simulating routing request
                prepareRoutingService( routingService );
                request.mockCGI = duplicate( cgi );
                request.mockCGI.path_info = arguments.route;
                request.mockCGI.script_name = "";
                request.mockCGI.domain = arguments.domain;

				// Capture the route request
				controller.getRequestService().requestCapture();

			} else {
				// Capture the request using our passed in event to execute
				controller.getRequestService().requestCapture( thisEvent );
			}

            if( settings.securityUDF( requestContext, requestContext.getCollection(), requestContext.getPrivateCollection(), log ) ?: true ) {

                // preProcess
                cbController.getInterceptorService().announce( "preProcess" );

                // Request Start Handler
                if ( len( cbController.getSetting( "RequestStartHandler" ) ) ) {
                    cbController.runEvent( cbController.getSetting( "RequestStartHandler" ), true );
                }

                thisEvent = requestContext.getCurrentEvent();

                // TEST EVENT EXECUTION
                if ( NOT requestContext.getIsNoExecution() ) {
                    // execute the event
                    handlerResults = cbController.runEvent(
                        event          = thisEvent,
                        defaultEvent   = true
                    );
                    // preLayout
                    cbController.getInterceptorService().announce( "preLayout" );

                    // Render Data?
                    renderData = requestContext.getRenderData();
                    if ( isStruct( renderData ) and NOT structIsEmpty( renderData ) ) {

                        requestContext.setValue( "cbox_render_data", renderData );
                        requestContext.setValue( "cbox_statusCode", renderData.statusCode );
                        renderedContent = cbController
                            .getDataMarshaller()
                            .marshallData( argumentCollection = renderData );

                    var contentType = renderData.contentType ?: '';
                    if( len( contentType ) ) {
                        if( !findNoCase( ";", contentType ) ) {
                            contentType &= "; charset=#renderData.encoding#";
                        }
                        requestContext.setHTTPHeader( name="Content-Type", value="#contentType#" );
                    }
                    	

                    }
                    // If we have handler results save them in our context for assertions
                    else if ( !isNull( local.handlerResults ) ) {
                        // Store raw results
                        requestContext.setValue( "cbox_handler_results", handlerResults );
                        requestContext.setValue( "cbox_statusCode", requestContext.getPrivateValue( 'mockStatusCode', 200 ) );
                        if ( isSimpleValue( handlerResults ) ) {
                            renderedContent = handlerResults;
                        } else {
                            renderedContent = serializeJSON( handlerResults );
                        }
                    }
                    // render layout/view pair
                    else {
                        renderedContent = cbcontroller.getRenderer()
                            .renderLayout(
                                module     = requestContext.getCurrentLayoutModule(),
                                viewModule = requestContext.getCurrentViewModule()
                            );

                        requestContext.setValue( "cbox_statusCode", requestContext.getPrivateValue( 'mockStatusCode', 200 ) );
                    }

                    // Pre Render
                    iData = { renderedContent : renderedContent };
                    cbController.getInterceptorService().announce( "preRender", iData );
                    renderedContent = iData.renderedContent;

                    // Store in collection for assertions
                    requestContext.setValue( "cbox_rendered_content", renderedContent );

                    // postRender
                    cbController.getInterceptorService().announce( "postRender" );
                }

                // Request End Handler
                if ( len( cbController.getSetting( "RequestEndHandler" ) ) ) {
                    cbController.runEvent( cbController.getSetting( "RequestEndHandler" ), true );
                }

                // postProcess
                cbController.getInterceptorService().announce( "postProcess" );
                
            // End custom security check
            } else {
                requestContext.setValue( "cbox_rendered_content", requestContext.getValue( "cbox_rendered_content", "Permission Denied" ) );
                requestContext.setValue( "cbox_statusCode", requestContext.getValue( "cbox_statusCode", "403" ) );
            }

		} catch ( any e ) {
            controller.getInterceptorService().announce( "onException", { exception : e } );
            // TODO: Adobe probably has another way to get the Java exception
            FRTransService.errorTransaction( FRTransaction, e.getPageException() );
            var headers = ( isnull( requestContext ) ? {} : requestContext.getPrivateValue( 'mockHTTPResponseHeaders', {} ) );
            headers[ 'Content-Type' ] = 'application/json';
            return {
                    // For dev, send the entire cfcatch struct
                    'body' : serializeJSON( ( controller.getSetting( 'environment' ) == 'development' ? e : { 'message' : e.message, 'detail' :  e.detail } ) ),
                    'statusCode' : 500,
                    'headers' : headers,
                    'source': generateSource( argumentCollection = arguments )
            };
		} finally {
            if( !isNull( FRTransaction ) ) {
                FRTransService.endTransaction( FRTransaction );
            }
        }

        return {
             'body' : requestContext.getValue( "cbox_rendered_content", "" ),
             'statusCode' : requestContext.getValue( "cbox_statusCode", "200" ),
             'headers' : requestContext.getPrivateValue( 'mockHTTPResponseHeaders', {} ),
             'source': generateSource( argumentCollection = arguments )
        };
   }

	function generateSource(
		string route,
		string event,
		struct params,
		struct headers,
		string method,
        string queryString,
        string domain
    ){
		var source = "#method# #settings.sourcePrefix##domain##route#";
        if( len( event ) ){
            source &= "?event=#event#";
        }
        if( len( queryString ) ){
            source &= "#( source contains '?' ? '&' : '?' )##queryString#";
        }
        return source;
	}

	function getRequestContext(){
		return getController()
			.getRequestService()
			.getContext();
	}

	/**
	 * Separate a route into two parts: the base route, and a query string collection
	 *
	 * @route a string containing the route with an optional query string (e.g. '/posts?recent=true')
	 *
	 * @return a struct containing the base route and a struct of query string parameters
	 */
	private struct function explodeRoute( required string route ){
		var routeParts = listToArray( urlDecode( arguments.route ), "?" );

		var queryParams = {};
		if ( arrayLen( routeParts ) > 1 ) {
			queryParams = parseQueryString( routeParts[ 2 ] );
		}

		return {
			route                 : routeParts[ 1 ],
			queryStringCollection : queryParams
		};
	}

	/**
	 * Parses a query string into a struct
	 *
	 * @queryString a query string from a URI
	 *
	 * @return a struct of query string parameters
	 */
	private struct function parseQueryString( required string queryString ){
		var queryParams = {};

		queryString
			.listToArray( "&" )
			.each( function( item ){
				queryParams[ urlDecode( item.getToken( 1, "=" ) ) ] = urlDecode( item.getToken( 2, "=" ) );
			} );

		return queryParams;
	}

    function prepareRoutingService( routingService ) {
        if( !structKeyExists( routingService, '_getCgiElement' ) ) {
            lock type="exclusive" name="prepareRoutingService" timeout="20" {
                if( !structKeyExists( routingService, '$mixer' ) ) {
                    routingService.$mixer = $mixer;
                    // Back up the original method
                    routingService.$mixer( '_getCgiElement', routingService.getCgiElement );
                    // And replace it with our impostor who will allow for a mock CGI scope
                    routingService.$mixer( 'getCgiElement', getCgiElement );
                }       
            }
        }
    }

    /////////////////////// MOCKING METHODS ////////////////////////////////////

    function getCgiElement( required cgiElement, required event ) {
        if( structKeyExists( request, 'mockCGI' ) ) {
            return request.mockCGI[ arguments.CGIElement ] ?: '';
        } else {
            return _getCgiElement( cgiElement, event );
        }
    }

	function getHTTPHeader( required header, defaultValue="" ){
		var headers = getPrivateValue( 'mockHTTPRequestHeaders', getHttpRequestData().headers );

		if( structKeyExists( headers, arguments.header ) ){
			return headers[ arguments.header ];
		}
		if( structKeyExists( arguments, "defaultValue" ) ){
			return arguments.defaultValue;
		}

		throw( message="Header #arguments.header# not found in HTTP headers",
			   detail="Headers found: #structKeyList( headers )#",
			   type="RequestContext.InvalidHTTPHeader");
	}

	function getHTTPMethod(){
		return getPrivateValue( 'mockHTTPMethod', 'GET' );
	}

    
	function setHTTPHeader(
		statusCode,
		statusText="",
		name,
		value=""
	){

		// status code?
		if( structKeyExists( arguments, "statusCode" ) ){
			setPrivateValue( 'mockStatusCode', arguments.statusCode );
		}
		// Name Exists
		else if( structKeyExists( arguments, "name" ) ){
			var headers = getPrivateValue( 'mockHTTPResponseHeaders', {} );
            headers[ arguments.name ] = arguments.value;
		} else {
			throw( message="Invalid header arguments",
				  detail="Pass in either a statusCode or name argument",
				  type="RequestContext.InvalidHTTPHeaderParameters" );
		}

		return this;
	}

    function $mixer( name, UDF ) {
        this[name]=UDF;
        variables[name]=UDF;
    }


}