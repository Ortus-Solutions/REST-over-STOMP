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

This module runs your Coldbox events inside of a "vacuum" which will not have any normal session scope.  This is fine for a stateless API or a simple app, but will not work great if you have an application which is very tightly coupled to a session scope.  The incoming requests will not have any cookies that you don't explicitly send and therefore can only authenticate the browser making the request if you send something along with the request to identity the user.  Make sure you use a JWT or other secure token and don't just blindly trust what the browser sends you. 

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
    'sourcePrefix' : 'myApp'
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
