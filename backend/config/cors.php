<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | The frontend is deployed separately (Cloudflare Pages), so every request
    | it makes to this API is cross-origin. Browsers block those unless the
    | API answers with the right headers -- that is what this file controls.
    |
    | Laravel's default only covers "api/*" paths. This app's routes live in
    | routes/web.php, so we use ['*'] to cover every route. That is safe here
    | because this application only serves the API.
    |
    */

    'paths' => ['*'],

    'allowed_methods' => ['*'],

    // The exact address of the frontend -- set FRONTEND_URL in .env.production.
    // "*" would also work, but it cannot be used together with cookies/logins.
    'allowed_origins' => [env('FRONTEND_URL', 'http://localhost:3000')],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    // Turn this on (and set SESSION_DOMAIN) only if you add cookie-based
    // login with Laravel Sanctum. Token-based auth does not need it.
    'supports_credentials' => false,

];
