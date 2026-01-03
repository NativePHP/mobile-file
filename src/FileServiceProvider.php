<?php

namespace Native\Mobile\Providers;

use Illuminate\Support\ServiceProvider;
use Native\Mobile\File;

class FileServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(File::class, function () {
            return new File;
        });
    }
}
