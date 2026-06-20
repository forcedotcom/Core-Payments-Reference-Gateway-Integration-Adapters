/**
 * Shared HTTP helpers for Stripe's application/x-www-form-urlencoded API.
 * Kept separate from {@link StripeAdapter} so the adapter class stays easier to read in a public sample.
 */
public with sharing class StripeHttpUtil
{
    public static HttpResponse doPost(String path, Map<String, String> params)
    {
        return doPost(path, params, null);
    }

    public static HttpResponse doPost(String path, Map<String, String> params, Map<String, String> headers)
    {
        commercepayments.PaymentsHttp http = new commercepayments.PaymentsHttp();
        HttpRequest request = new HttpRequest();
        request.setEndpoint('/v1/' + path);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        if (headers != null) {
            for (String headerName : headers.keySet()) {
                request.setHeader(headerName, headers.get(headerName));
            }
        }
        request.setBody(urlEncodedParams(params));
        return http.send(request);
    }

    /**
     * Key/value body for Stripe. Callers may pass values that must remain un-encoded so
     * PaymentsNamedConnection can substitute secrets at callout time.
     */
    public static String urlEncodedParams(Map<String, String> params)
    {
        String body = '';
        Boolean first = true;
        for (String key : params.keySet()) {
            if (first) {
                first = false;
            } else {
                body += '&';
            }
            body += urlEncode(key) + '=' + params.get(key);
        }
        return body;
    }

    public static String urlEncode(String str)
    {
        if (str == null) {
            return null;
        }
        return EncodingUtil.urlEncode(str, 'UTF-8');
    }
}
