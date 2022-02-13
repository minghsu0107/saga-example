# Saga Example
A saga pattern implementation dealing with distributed transactions in a Microservices architecture, written in Golang.

Related repositories (10K+ LOC):
- https://github.com/minghsu0107/saga-purchase
- https://github.com/minghsu0107/saga-account
- https://github.com/minghsu0107/saga-product
- https://github.com/minghsu0107/saga-pb

An all-in-one docker-compose deployment is provided, which includes the following components:
- Traefik - edge proxy that is responsible for external traffic routing and internal grpc load-balancing. 
- [Account service](https://github.com/minghsu0107/saga-account) - service that handles login, sigup, authentication, and token management.
- [Purchase service](https://github.com/minghsu0107/saga-purchase) - service that creates purchase and streams results of each saga step.
- [Transaction services](https://github.com/minghsu0107/saga-product)
  - Product service - service that creates and checks products; updates product inventories.
  - Order service - service that creates and queries orders.
  - Payment service - service that creates and queries payments.
  - Orchestrator service - **stateless** saga orchestrator.
- Local databases
  - Account database (MySQL 8.0)
  - Product database (MySQL 8.0)
  - Payment database (MySQL 8.0)
  - Order database (MySQL 8.0)
- Six-node redis cluster 
  - As an in-memory cache for account, product, order, and payment.
  - As bloom/Cuckoo filters for preventing cache penetration (using [Redis Bloom](https://oss.redis.com/redisbloom/)).
  - As distributed locks for preventing cache avalanche
  - As a pub/sub for local cache invalidation.
  - As a streaming platform for obtaining real-time purchase result.
- Observibility
  - Prometheus - pulling metrics from all services.
  - Jaeger - preserving and querying tracing spans accross service boundaries.
- NATS Streaming - message broker for saga commands and events.

The following diagram shows a brief overview of the architecture.

<img width="1223" alt="image" src="https://user-images.githubusercontent.com/50090692/151692728-d8a1cd30-5b6b-4b97-93a9-8960ba8fefc7.png">

This diagram omits cache data flow, bloom filters, and local databases.
## Usage
To run all services locally via docker-compose, execute:
```bash
./run.sh run
```
This will bootsrap all services as well as their replicas in Docker containers.

To stop all services, execute:
```bash
./run.sh stop
```
### Account Service
First, we need to signup a new user:
```bash
curl -X POST localhost/api/account/auth/signup \
    --data '{"password":"abcd5432","firstname":"ming","lastname":"hsu","email":"ming@ming.com","address":"taipei","phone_number":"1234567"}'
```
User account login:
```bash
curl -X POST localhost/api/account/auth/login \
    --data '{"email":"ming@ming.com","password":"abcd5432"}'
```
This will return a new token pair (refresh token + access token). We should provide the access token in the `Authorization` header for those APIs with authentication.

We could obtain a new token pair by refreshing with the refresh token:
```bash
curl -X POST localhost/api/account/auth/refresh \
    --data '{"refresh_token":"<refresh_token>"}'
```
Get user personal information:
```bash
curl localhost/api/account/info/person -H "Authorization: bearer <access_token>"
```
Update user personal information:
```bash
curl -X PUT localhost/api/account/info/person -H "Authorization: bearer <access_token>" \
    --data '{"firstname":"newfirst","lastname":"newlast","email":"ming3@ming.com"}'
```
Get user shipping information:
```bash
curl localhost/api/account/info/shipping -H "Authorization: bearer <access_token>"
```
Update user shipping information:
```bash
curl -X PUT localhost/api/account/info/shipping -H "Authorization: bearer <access_token>" \
    --data '{"address":"japan","phone_number":"54321"}'
```
### Product Service
Next, let's create some new products:
```bash
curl -X POST localhost/api/product \
     --data '{"name": "product1","description":"first product","brand_name":"mingbrand","price":100,"inventory":1000}'
curl -X POST localhost/api/product \
     --data '{"name": "product2","description":"second product","brand_name":"mingbrand","price":100,"inventory":10}'
```
The API will return the ID of the created product.

List all products with pagination:
```bash
curl "localhost/api/products?offset=0&size=100"
```
This will return a list of product catalog, including its ID, name, price, and current inventory.

Get product details:
```bash
curl "localhost/api/product/<product_id>"
```
This will return the name, description, brand, price and cached inventory of the queried product.
### Purchase Service
Here comes the core part. We are going to create a new purchase, which sends a new purchase event to the saga orchestrator and triggers distributed transactions. It will return the ID of the new purchase when success.
```bash
curl -X POST localhost/api/purchase -H "Authorization: bearer <access_token>" \
    --data '{"purchase_items":[{"product_id":<product_id>,"amount":1}],"payment":{"currency_code":"NT"}}'
```

After creating a purchase, we can subscribe to `/api/purchase/result` to receive **realtime transaction results**. The purchase service pushes results using [server-sent events (SSE)](https://developer.mozilla.org/zh-TW/docs/Web/API/Server-sent_events/Using_server-sent_events). The following code example shows how to subscribe to server-sent events using Javascript. We will use [this library](https://github.com/Yaffle/EventSource) to send SSE request with `Authorization` header.

```javascript
var script = document.createElement('script');script.src = "https://unpkg.com/event-source-polyfill@1.0.9/src/eventsource.js";document.getElementsByTagName('head')[0].appendChild(script);
var es = new EventSourcePolyfill('http://localhost/api/purchase/result', {
  headers: {
    'Authorization': 'bearer <access_token>'
  },
});
var listener = function (event) {
  var data = JSON.stringify(event.data);
  console.log(data);
};
es.addEventListener("data", listener);
```

If the subscription is successful, we would receive realtime results like the following:

<img width="1470" alt="image" src="https://user-images.githubusercontent.com/50090692/151049964-b4752356-ca9f-4e90-ae85-247e538778b9.png">

### Order Service

Next, we could check whether our order is successfully created:
```bash 
curl "localhost/api/order/<payment_id>"  -H "Authorization: bearer <access_token>"
```
### Payment Service
Finally, we could check whether our payment is successfully created:
```bash
curl "localhost/api/payment/<payment_id>"  -H "Authorization: bearer <access_token>"
```
## Observibility
All services could be configured to expose Prometheus metrics and send tracing spans. By default, all services have their Prometheus metric endpoints exposed on port `8080`. As for distributed tracing, we could simply enable it by setting environment variable `JAEGER_URL` to the Jaeger collection endpoint.

To check whether all services are alive, visit Prometheus at `http://localhost:9090/targets`.

<img width="1792" alt="image" src="https://user-images.githubusercontent.com/50090692/150729950-aea0687a-ee0f-41f1-8220-a9febcf20a72.png">

Visit the Jaeger web UI at `http://localhost:16686`. We can check all tracing spans of our API calling chains, starting from Traefik. For example, the following figure shows a request that queries `/api/order/<order_id>`. We can see that once order service receives the request, it authenticates the request first by calling `auth.AuthService.Auth`, a gRPC authentication API provided by account service. If the authentication is successful, order service will continue processing the request. To obtain a complete order, order service will ask product service for details of purchased products through another gRPC call `product.ProductService.GetProducts`.

<img width="1792" alt="image" src="https://user-images.githubusercontent.com/50090692/153759779-b60c1086-35dd-4b08-890b-6b925b0f9374.png">

Let's see a more complexed example. This figure shows how transaction services interact with each other after we create a new purchase. The authentication process is similar to the previous example. After purchase service authenticates the request successfully, it publishes a `CreatePurchaseCmd` event to the message broker. Orchestrator service will then receive the event and start saga transactions. The following diagram show all related traces in a single purchase, including traces of streaming results and Redis operations.

<img width="1792" alt="image" src="https://user-images.githubusercontent.com/50090692/153759967-43e2d4c4-83cf-4cad-a94d-3446b3b0c442.png">

Each transaction service adds the current span context to the event before publishing it. When a subscriber receives a new event, it extracts the span context from the event payload. This extracted span then becomes the parent span of the current span. By doing this, we could generate a full pub/sub calling chain across all transactions. 

In addition, Jaeger will create service topologies for our spans. The following figure shows the topology when a client creates a new purchase.

![](https://i.imgur.com/gJHzNMN.png)
