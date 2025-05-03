use lambda_http::{run, service_fn, Body, Error, Request, Response};
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use serde_json::json;
use std::str::FromStr;
use tracing::{error, info};

const BINANCE_API_BASE: &str = "https://api2.binance.com";

/// Main function entry point for both Lambda and local testing
#[tokio::main]
async fn main() -> Result<(), Error> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .without_time()
        .init();

    info!("Binance API Proxy Lambda initialized");

    // Determine if we're running locally or in AWS Lambda
    if std::env::var("AWS_LAMBDA_RUNTIME_API").is_ok() {
        // Running in AWS Lambda
        info!("Running in AWS Lambda environment");
        run(service_fn(proxy_function)).await
    } else {
        // Local development mode
        info!("Running in local development mode");
        run_local_http_server().await
    }
}

/// Run a local HTTP server for testing
async fn run_local_http_server() -> Result<(), Error> {
    use hyper::service::{make_service_fn, service_fn as hyper_service_fn};
    use hyper::{Body as HyperBody, Request as HyperRequest, Response as HyperResponse, Server};
    use std::convert::Infallible;
    use std::net::SocketAddr;

    // Define the address to listen on
    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    info!("Starting local server at http://{}", addr);

    // Convert between Hyper types and Lambda types
    let make_svc = make_service_fn(|_conn| async {
        Ok::<_, Infallible>(hyper_service_fn(
            |req: HyperRequest<HyperBody>| async move {
                // Convert Hyper request to Lambda request
                let (parts, body) = req.into_parts();
                let body_bytes = hyper::body::to_bytes(body).await.unwrap_or_default();
                
                let lambda_body = if body_bytes.is_empty() {
                    Body::Empty
                } else {
                    Body::Text(String::from_utf8_lossy(&body_bytes).to_string())
                };
                
                let mut lambda_req = Request::new(lambda_body);
                *lambda_req.method_mut() = parts.method;
                *lambda_req.uri_mut() = parts.uri;
                *lambda_req.headers_mut() = parts.headers;
                
                // Process the request with our Lambda handler
                let lambda_resp = match proxy_function(lambda_req).await {
                    Ok(resp) => resp,
                    Err(e) => {
                        error!("Error processing request: {:?}", e);
                        Response::builder()
                            .status(500)
                            .body(Body::Text(format!("Internal Server Error: {}", e)))
                            .unwrap_or_else(|_| Response::builder()
                                .status(500)
                                .body(Body::Text("Critical error".to_string()))
                                .unwrap())
                    }
                };
                
                // Convert Lambda response to Hyper response
                let mut resp_builder = HyperResponse::builder()
                    .status(lambda_resp.status());
                
                // Add headers
                for (key, value) in lambda_resp.headers() {
                    resp_builder = resp_builder.header(key, value);
                }
                
                // Add body
                let hyper_body = match lambda_resp.body() {
                    Body::Empty => HyperBody::empty(),
                    Body::Text(text) => HyperBody::from(text.clone()),
                    Body::Binary(bytes) => HyperBody::from(bytes.clone()),
                };
                
                Ok::<_, Infallible>(resp_builder.body(hyper_body).unwrap())
            },
        ))
    });

    // Start the server
    let server = Server::bind(&addr).serve(make_svc);
    info!("Local server running. Press Ctrl+C to stop.");
    
    // Run the server until terminated
    if let Err(e) = server.await {
        error!("Server error: {}", e);
        return Err(Box::new(e));
    }
    
    Ok(())
}

/// Handles the Lambda request and proxies to Binance API
async fn proxy_function(event: Request) -> Result<Response<Body>, Error> {
    info!("Received request: {:?}", event);
    
    // Extract path and query parameters
    let path = event.uri().path();
    let query = event.uri().query().unwrap_or("");
    
    // Ensure the path starts with /api/ 
    if !path.starts_with("/api/") {
        return Ok(Response::builder()
            .status(400)
            .body(Body::from(json!({"error": "Path must start with /api/"}).to_string()))?);
    }
    
    // Build the full Binance URL
    let binance_url = format!("{}{}", BINANCE_API_BASE, path);
    let full_url = if query.is_empty() {
        binance_url
    } else {
        format!("{}?{}", binance_url, query)
    };
    
    info!("Proxying request to: {}", full_url);
    
    // Forward the request to Binance
    let client = reqwest::Client::new();
    let mut req_builder = match event.method() {
        &http::Method::GET => client.get(&full_url),
        &http::Method::POST => client.post(&full_url),
        &http::Method::PUT => client.put(&full_url),
        &http::Method::DELETE => client.delete(&full_url),
        _ => {
            return Ok(Response::builder()
                .status(405)
                .body(Body::from(json!({"error": "Method not allowed"}).to_string()))?);
        }
    };
    
    // Forward headers from the original request
    let mut headers = HeaderMap::new();
    for (key, value) in event.headers() {
        if key != "host" {
            if let Ok(header_name) = HeaderName::from_str(key.as_str()) {
                if let Ok(header_value) = HeaderValue::from_str(value.to_str().unwrap_or_default()) {
                    headers.insert(header_name, header_value);
                }
            }
        }
    }
    req_builder = req_builder.headers(headers);

    // Forward the request body for non-GET requests
    if event.method() != &http::Method::GET {
        if let Body::Text(body_text) = event.body() {
            req_builder = req_builder.body(body_text.clone());
        }
    }
    
    // Execute the request to Binance
    match req_builder.send().await {
        Ok(binance_response) => {
            let status = binance_response.status();
            let headers = binance_response.headers().clone();
            let body_bytes = binance_response.bytes().await?;
            
            // Build the response to the client
            let mut response_builder = Response::builder().status(status);
            
            // Forward relevant headers from Binance response
            for (key, value) in headers {
                if let Some(key) = key {
                    response_builder = response_builder.header(key.as_str(), value);
                }
            }
            
            // Convert bytes to Vec<u8> which can be used with Body::from
            let body_vec = body_bytes.to_vec();
            Ok(response_builder.body(Body::from(body_vec))?)
        },
        Err(err) => {
            error!("Error proxying to Binance: {:?}", err);
            Ok(Response::builder()
                .status(500)
                .body(Body::from(json!({"error": format!("Failed to proxy request: {}", err)}).to_string()))?)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use http::Method;
    
    #[tokio::test]
    async fn test_proxy_function_invalid_path() {
        let mut request = Request::default();
        *request.method_mut() = Method::GET;
        *request.uri_mut() = "/invalid/path".parse().unwrap();
        
        let response = proxy_function(request).await.unwrap();
        assert_eq!(response.status(), 400);
    }
    
    #[tokio::test]
    async fn test_proxy_function_unsupported_method() {
        let mut request = Request::default();
        *request.method_mut() = Method::PATCH; // PATCH is not supported in the proxy
        *request.uri_mut() = "/api/v3/time".parse().unwrap();
        
        let response = proxy_function(request).await.unwrap();
        assert_eq!(response.status(), 405);
        
        // Verify error message in response body
        if let Body::Text(body_text) = response.body() {
            assert!(body_text.contains("Method not allowed"));
        } else {
            panic!("Expected Text body");
        }
    }
}
