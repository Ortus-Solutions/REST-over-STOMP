component {

	this.modelNamespace     = "REST-over-STOMP";
	this.cfmapping          = "REST-over-STOMP";
	this.autoMapModels      = true;
	this.dependencies       = [ 'rabbitsdk' ];

	function configure() {
		settings = {
			'incomingQueueName' : 'API-Requests',
			'autoDeclareIncomingQueue' : true,
			'consumerThreads' : 30,
			'debugMessages' : false,
			'replyToUDF' : ( event, rc, prc, message, log )=>message.getHeader( 'reply_to', '' ),
			'securityUDF' : ( event, rc, prc, message, log )=>true,
			'sourcePrefix' : ''
		};

	}

	/**
	 * Fired when the module is registered and activated.
	 */
	function onLoad() {
		wirebox.getInstance( 'WebsocketHandler@REST-over-STOMP' ).startRabbitConsumer();
	}

	/**
	 * Fired when the module is unregistered and unloaded
	 */
	function onUnload() {
		wirebox.getInstance( 'WebsocketHandler@REST-over-STOMP' ).stopRabbitConsumer();
	}

}
