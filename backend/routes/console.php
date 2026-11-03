<?php

use Illuminate\Support\Facades\Artisan;

Artisan::command('happy:about', function () {
    $this->comment('Happy Live API scaffold');
})->purpose('Display Happy Live API information');
