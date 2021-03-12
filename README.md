# REST over STOMP

A ColdBox module to expose remote events via a STOMP websocket over RabbitMQ

## Purpose

This module adds functionality to an existing ColdBox application which allows you to push the response of any Coldbox event or API call out over a websocket channel to any browser listening on that channel.  This allows for the following:

* Browser can request data and receive it async
* Any random server-side process can simply decide to push fresh data out to browser via sending a message to a Rabbit Queue
* Each user can subscribe to a custom topic specific to them so you have a direct data bus to any users' browser
* Unlike Ajax calls, there is no HTTPS/TCP negotiation of each request since the websocket is a persistent connection to the server
* Payload can be JSON, text, or HTML

It's worth noting that you don't actually need to have a REST API to use this module.  While I named it `REST-over-STOMP` since I intended to use it with a REST API, it is capable of running ANY VALID ColdBox event through the event name or SES Route and will return whatever that event normally returns to a browser.

## Requirements

In order to use this module you need to have
* Coldbox MVC - https://coldbox.ortusbooks.com/getting-started/getting-started-guide
* RabbitMQ - https://www.rabbitmq.com/
* RabbitMQ Stomp plugin - https://www.rabbitmq.com/stomp.html
* RabbitMQ Web Stomp Plugin - https://www.rabbitmq.com/web-stomp.html
* Some sort of Stomp.js lib - https://www.npmjs.com/package/@stomp/stompjs
* A wild spirit of adventure

Note the Stomp.js library above is a Node lib but can also be used directly in your browser.  There are several Stomp.js libs and I suppose they all work, but this one seems to be supported well.

This module includes as a dependency:
* RabbitSDK for CFML - https://github.com/Ortus-Solutions/RabbitSDK/blob/master/README.md

This module runs your Coldbox events inside of a "vacuum" which will not have any normal session scope.  This is fine for a stateless API or a simple app, but will not work great if you have an application which is very tightly coupled to a session scope.  You may need to refactor parts of your app or API to wrap an abstraction around these aspects.  The incoming requests will also not have any cookies that you don't explicitly send and therefore can only authenticate the browser making the request if you send something along with the request to identity the user.  Make sure you use a JWT or other secure token and don't just blindly trust what the browser sends you. 

## Installation

To get started, it is assumed you have RabbitMQ intalled and have a basic understanding of how it works.  Install the `REST-over-STOMP` module into your app like so:
```bash
insatll REST-over-STOMP
```
You can manually create a queue in rabbit to receive requests for processing, but I recommend letting the module auto-create the queue for you when it loads.  

Next download the Stomp.js library of your choice and incude it in your app.

```html
<!-- Include from CDN for better performance, alternatively you can locally copy as well -->
<script src="https://cdn.jsdelivr.net/npm/@stomp/stompjs@6.0.0/bundles/stomp.umd.min.js"></script>
```

## Configuration

The `REST-over-STOMP` module whcih lives inside your ColdBox application will startup Rabbit consumer threads lstening in the background of your Coldbox app.  These threads will be listneing the entire time the app is up.  When you reinit the framework and the module reloads, it will shutdown the listner threads and start new ones.  These theads will subscribe to a queue for incoming requests and then run the ColdBox event that was requested and push the data out over a Rabbit topic which will eventually end up as a STOMP websocket in any browsers subscribed to that topic. 

### ColdBox Config

You can configure the module in your `/config/Coldbox.cfc` file.  You'll also need to configure the `rabbitSDK` module if you're not already using it. Adding these structs to your module settings:

```js
moduleSettings = {
  "rabbitsdk" = {
    "host" = "rabbitHost",
    "username" = "adminUser",
    "password" = "adminPass"
  },
  "rest-over-stomp" = {
    'incomingQueueName' : 'API-Requests',
    'autoDeclareIncomingQueue' : true,
    'consumerThreads' : 30,
    'debugMessages' : true,
    'replyToUDF' : ( event, rc, prc, message, log )=>message.getHeader( 'reply_to', '' ),
    'securityUDF' : ( event, rc, prc, log )=>true,
    'sourcePrefix' : 'myApp-prefix'
  }
}
```

#### `incomingQueueName`
Name of Rabbit queue that the consumer threads will listen to for incoming requests.  Messages can be pushed to this queue via an authenticated STOMP connection or from a back-end server process of any langauge.  

Default value is `API-Requests`.

#### `autoDeclareIncomingQueue`
When set to `true`, the REST over STOMP module will automaticaly delcare the `incomingQueueName` queue in Rabbit if it doesn't already exist.  

Default vaue is `true`.

#### `consumerThreads`
Number of Rabbit consumer threads to start.  The number ultimatley controls how many concurrent REST over STOMP requests can be proecssed at the same time.  If more messages come in than threads exist, those messages will simply be quueued in Rabbit until there is a thread available to process it.  

Default value is `30`

#### `debugMessages`
When set to `true`, additional debugging information about every incoming REST over STOMP message and the outgoing reponse will be logged to a LogBox logger named after the models in this module.  In a CommandBox server if you have a ConsoleAppender configured in ColdBox,  you can easily see these messages like so:
```bash
server log --follow
```
This is great for development debugging, but not recommented in production.  In addition to this setting, the normal Logbox settings can be used to configure messages from this module.  This setting simply turns on additional `DEBUG` level messages.

Default value is `false`;  

#### `replyToUDF`
This is a closure which allows you to control what topic name the return message will get sent to.  The UDF must return a string which is the topic name in Rabbit to reply to and the signature of the UDF is as follows:
```js
( event, rc, prc, message, log )=>{}
```
* `event` - The RequestContext object from the ColdBox request
* `rc` - The Request Collection from the ColdBox request
* `prc` - The Private Request Collection from the ColdBox request
* `message` - The RabbitSDK message object.  https://github.com/Ortus-Solutions/RabbitSDK#message
* `log` - The logbox logger from the REST over STOMP module

The default implementation is
```js
'replyToUDF' : ( event, rc, prc, message, log )=>message.getHeader( 'reply_to', '' ),
```
which will look for a header in the STOMP websocket message called `reply_to`.  Keep in mind, this header is controlled by the client who sent the message, which may be a web browser.  If you cannot trust the browser, you can instead force the reply to topic based on the user that is authenticated, assuming the incoming request carried a JWT or other auth token which can be used to determine who is making the request.  (This example assumes you are using `cbsecurity` and JWT (JSON Web Tokens) in your app)

```js
// Force the reply to topic to use the userID stored in the incoming JWT 
'replyToUDF' : ( event, rc, prc, message, log )=>{
  return 'api-responses.' & controller
    .getWireBox()
    .getInstance( 'JwtService@cbsecurity' )
    .decode( event.getHTTPHeader( "JWT", "" ) ).sub;
},
```
It's worth noting that even though the example above appears to be accessing an HTTP header, there are not actually HTTP headers inside the Rabbit Consumer thread that runs the code. THe header will be sent inside the STOMP websocket message and the REST over STOMP module will spoof these headers to the `event.getHTTPHeader()` call can see it.  This is why it is very important to always use the ColdBox facades to access headers.  If you use the CFML function `getHTTPRequestData().headers` directly it won't work!

#### `securityUDF`
When the REST over STOMP Rabbit consumer thread runs an incoming request, it will fire all the normal request lifecycle events that you expect:
* preProcess interceptor
* RequestStartHandler
* RequestEndHandler
* preLayout interceptor
* preRender interceptor
* postRender interceptor
* postProcess interceptor
* onException interceptor

This means that if your app or API is secured by an interceptor, it will fire as usual.  However, if you want to provide an additional security check, the `securtyUDF` will be executed inside the Rabbit consumer thread prior to each request and before ANY of the interceptors or request lifecyle handler events fire.  The signature (and default implementation) of the UDF is:
```js
'securityUDF' : ( event, rc, prc, log )=>true,
```
* `event` - The RequestContext object from the ColdBox request
* `rc` - The Request Collection from the ColdBox request
* `prc` - The Private Request Collection from the ColdBox request
* `log` - The logbox logger from the REST over STOMP module

The UDF can have the following behaviors:
* Return nothing, which allows the request to continue
* Return `true`, which allows the request to continue
* Return `false`, which will abort the request
* Override the event with `event.overrideEvent( 'new.evnet' )`
* Throw an exception with `throw( 'not likely' );` which will abort the request and trigger the `onException` interceptor
* Directly override the content and status code of the reponse like so:

```js
'securityUDF' : ( event, rc, prc, log )=>{
  rc.cbox_rendered_content = "go away";
  rc.cbox_statusCode = 404;
  return false;
},
```

#### `sourcePrefix`
Since responses arrive back at the browser in an aynsc fasion-- or in some cases a REST over STOMP delivery may arrive at the browser unexpectedly from a back-end process, it is neccessary for the browser to be able to identify what it has just received.  The `source` key in the response (covered below) will include this prefix if you set it to identify what app the data came from.  It is possible to have `REST-over-STOMP` installed in more than on ColdBox app, each capable of sending the results of their events to any given browser.

The default value is an empty string ( `""` )

## Usage

You can create a simple Stomp.js subscription like so.  This handles the connection to Rabbit and sets up some simple code to respond when a STOMP websocket message comes in.

```js

const stompConfig = {
  connectHeaders: {
    login: "guest",
    passcode: "guest"
  },

  brokerURL: "ws://localhost:15674/ws",
  
  // Keep it off for production, it can be quite verbose
  debug: function (str) {
    console.log('STOMP: ' + str);
  },

  // If disconnected, it will retry after 200ms
  reconnectDelay: 200,

  // Subscriptions should be done inside onConnect as those need to reinstated when the broker reconnects
  onConnect: function (frame) {
    // Make this topic dynamic so each user gets their own
    const subscription = stompClient.subscribe('/topic/api-responses.Brad-Wood', function (message) {
      // This will only exist if you pass it with the request
      console.log( message.headers.correlationId  )

      const payload = JSON.parse(message.body);
      var data = payload.body;
      if( payload.headers && 'Content-Type' in payload.headers && payload.headers['Content-Type'].toUpperCase().includes( 'JSON' ) ) {
        data = JSON.parse( payload.body );
      }
      console.log( data )
    });
  }

};

stompClient = new StompJs.Client(stompConfig);
stompClient.activate();
```
Now, you can request the results of a ColdBox event in your browser via JS like so:
```js
var data = {
  destination: '/queue/API-Requests',
    body: JSON.stringify({
      "route": "/api/v1/echo",
      "headers": {
        "JWT": JWTValue
      },
      "method": "GET"
    }),
    headers:{
      // The RabbitSDK uses this to know to desearlialize the STOMP body
      "_autoJSON":true,
      "reply_to":"api-responses.Brad-Wood",
      "correlationId":123456
    }
};
stompClient.publish( data );
```
Note the response comes back asyncronously.  The callback that processes a reponse is in the code block above.  It's up to your code to introspect the incoming payload, decide what it is, where it came from, and what to do with it.

You can request a payload be sent from a server-side process using the CFML RabbitSDK.  (Or for that matter, any valid programming language can send a message to Rabbit to kick off this process)

```js
rabbitClient
  .publish(
    body = {
      "route": "/api/v1/echo",
      "headers": {
        "X-Api-Key":"..."
      },
      "method": "GET"
    },
    routingKey='API-Requests',
    props={
      "headers" : {
        "reply_to" : "api-responses.Brad-Wood",
        "correlationId":123456
      }
    }
  );
```

This is all pretty rough and there are many ways to accompish it.  Just ensure you think through:
* Authenticating browsers to Rabbit (this is where the HTTP backend auth comes in)  DON'T HARDCODE A USER/PASS IN YOUR APP'S JS FILES!
* Authenticating requests to your ColdBox app.  This is a separate concern from the bullet above.  The user/JWT in your browser only provides the rights for the client to send the message to the Rabbit queue.  When the message arrives at the Rabbit consumer, you need to decide if that incoming request can be served by your Coldbox app.  
* Consider what you will use for your topic names, and ensure your HTTP backend auth implementation in the fist bullet only allows a user to subscribe to their OWN TOPIC.  

It's fairly easy to get a proof of concept of all this going, but it's a lot more work to ensure you've locked everything down from a security standpoint.  Remember any browser on the internet can try and connect to your Rabbit STOMP server.  

### Request structure

Whether you request a REST over STOMP response from a browser or the RabbitSDK directly, the body of the message follows the same format.  It roughly mimics all the data that is part of a standard HTTP request, even though your REST over STOMP request will NOT be send via HTTP, but embedded in a STOMP websocket message instead.
```js
{
  // Struct of HTTP headers.  These are different from the RabbitMQ message headers!
  headers : {},
  // Struct of form/url values. These will appear in the "rc" struct in ColdBox
  params : {},
  // The SES route such as /main/index or /api/user  This is mutually exclusive with event
  route : '',
  // The name of the ColdBox event such as main.index or api:user.index  This is mutually exclusive with route
  event : '',
  // HTTP verb for the request.  This affect's ColdBox's routing and is avilable via event.getHTTPMethod()  Defaults to GET
  method : 'GET',
  // Query string for the request.  Any values passed here will be appended to the "params" struct above
  queryString : '',
  // Used for domain-based routing in the ColdBox router
  domain : ''
}
```
All of the properties above are optional.  If you were to send nothing, you could get back the result of a GET to the default event in the ColdBox app, whcih would be the equivalent of just htiting the site's default page in your browser.  Also remember, your ColdBox app should not directly touch the real `URL`, `form`, `cgi` scopes nor `getHTTPRequestData()` in CFML or it will not be able to see this data.  Instead, ensure your app uses the RequestContext (the `event` object) helpers, and the `rc` struct for all data.  This allows the REST over STOMP module to spoof all of these data so your app won't be able to tell the difference between a normal HTTP request and processing a REST over STOMP request inside of a Rabbit consumer thread.

### Request structure

The STOMP websocket message when it arrives at your browser will have the following body.  The actual STOMP body will be a string so you will need to deserialize it in your JS code.
```js
{
     'body' : '{ "data" : "Welcome to ColdBox REST" }',
     'statusCode' : 200,
     'headers' : {
       "Content-Type": "application/JSON"
     },
     'source': 'GET myApp-prefix/api/v1/echo'
};
```
It's important to remmeber that the response won't neccessariy be JSON.  It could be HTML or plain text.  It's up to you to look at the HTTP headers in the response to decide what it is.  In the example above, the content is JSON, so you could then need to deserialize the body of the response.   Any HTTP headers you set in your ColdBox request will appear in the `headers` struct SO LONG AS you use
```js
event.setHTTPHeader( "name", "value" )
```
Remember to always use the ColdBox helpers and never touch CF's plumbing directly.

#### `Source`

The `source` is so you can identify a response when it reaches your browser.  It tells you what remove server it came from and what Coldbox event or route it is the result of.  Since REST over STOMP messages can be triggered asyncronously or requested from an external process, the browser needs to be able to identify what it's getting.

The recipe for the `source` is like this
```
<method> <sourcePrefix><domain>[<route>][?event=<event>][?<queryString>]
```
So, for example, if the `sourcePrefix` for our app (configured in `config/Coldbox.cfc`) is `myApp-prefix` and if you ask for a `GET` to the `/api/v1/echo` route with no query string, then the source would be:
```
GET myApp-prefix/api/v1/echo
```

#### `correlationId`

IF you send more than one request to the same endpoint, you can add a correlationId to the request message as a STOMP websocket header (not the same as an HTTP request header).  When the REST over STOMP module ships back the reponse, it will add the `correlationId` as a STOMP header (again, not the same as an HTTP response header) and you can access it in your JS in the headers of the message object. The examples above show how this works.  `correlationId` is optional. 