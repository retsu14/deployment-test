<?php

use Illuminate\Support\Facades\Route;

// Health check -- hit by the nginx healthcheck and by `curl https://api.yoursite.com/up`.
Route::get('/up', function () {
    if (file_exists(storage_path('framework/down'))) {
        abort(503);
    }

    return response('Application up', 200)->header('Content-Type', 'text/plain');
});

Route::get('/', function () {
    return view('welcome');
});
