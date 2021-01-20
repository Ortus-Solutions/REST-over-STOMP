component accessors=true singleton {
    property name='rabbitClient' inject='RabbitClient@rabbitsdk';
    property name='RequestBridge' inject='RequestBridge@REST-over-STOMP';
    property name='settings' inject='coldbox:modulesettings:REST-over-STOMP';
    property name='log' inject='logbox:logger:{this}';


    function startRabbitConsumer() {

        log.info( 'Starting #settings.consumerThreads# Rabbit Consumer(s)' );

        if( settings.autoDeclareIncomingQueue ) {
            rabbitClient.queueDeclare(
                name=settings.incomingQueueName,
                durable=true
            );
        }
        cfloop( from=1, to="#settings.consumerThreads#", item="local.i" ) {
            rabbitClient.startConsumer( settings.incomingQueueName, ( message, channel, log )=>{
                if( settings.debugMessages ) {
                    log.info( 'Message received to [#settings.incomingQueueName#]', message.getBody() );
                }
                var requestObj = message.getBody();

                if( !isStruct( requestObj ) ) {
                    log.warn( 'Message body not struct, ignoring.' );
                    return;
                }

                // Defaults
                requestObj.append( {
                    headers : {},
                    params : {},
                    route : '',
                    event : '',
                    method : 'GET',
                    queryString : '',
                    // Used for domain-based routing in the ColdBox router
                    domain : ''
                }, false );
                
                // RequestBridge is a transient.  One for each request.
                var responseObj = RequestBridge.processRequest(
                    argumentCollection = requestObj
                );


                var requestContext  = RequestBridge.getRequestContext();
                var replyTo = settings.replyToUDF( requestContext, requestContext.getCollection(), requestContext.getPrivateCollection(), message, log );
                if( !len( replyTo ) ) {
                    log.error( 'Reply to routing key cannot be found. Please check your replyToUDF setting' );
                    return;
                }

                if( settings.debugMessages ) {
                    log.info( 'Sending reply to [#replyTo#]', responseObj );
                }

                channel.publish(
                    exchange='amq.topic',
                    routingKey=replyTo,
                    body=responseObj,
                    props={
                        'headers' : {
                            'correlationID' : message.getHeader( "correlationId", "" )
                        }
                    }
                );
            } );
        }

    }
    
    function stopRabbitConsumer() {
        log.info( 'Stopping Rabbit Consumers' );
        rabbitClient.shutdown();
    }

}