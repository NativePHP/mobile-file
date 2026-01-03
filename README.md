# File Plugin for NativePHP Mobile

File operations (move, copy) for NativePHP Mobile applications.

## Overview

The File API provides cross-platform file manipulation operations.

## Installation

```bash
composer require nativephp/mobile-file
```

## Usage

### PHP (Livewire/Blade)

```php
use Native\Mobile\Facades\File;

// Move a file
$result = File::move('/path/to/source.txt', '/path/to/destination.txt');

if ($result['success']) {
    echo 'File moved successfully!';
}

// Copy a file
$result = File::copy('/path/to/source.txt', '/path/to/copy.txt');

if ($result['success']) {
    echo 'File copied successfully!';
}
```

### JavaScript (Vue/React/Inertia)

```js
import { file } from '#nativephp';

// Move a file
const result = await file.move('/path/to/source.txt', '/path/to/destination.txt');

if (result.success) {
    console.log('File moved successfully!');
}

// Copy a file
const result = await file.copy('/path/to/source.txt', '/path/to/copy.txt');

if (result.success) {
    console.log('File copied successfully!');
}
```

## Methods

### `move(string $from, string $to): array`

Moves a file from source to destination.

| Parameter | Type | Description |
|-----------|------|-------------|
| `from` | string | Source file path |
| `to` | string | Destination file path |

**Returns:**
- `success: bool` - Whether the operation succeeded
- `error: string` - Error message if operation failed (optional)

### `copy(string $from, string $to): array`

Copies a file from source to destination.

| Parameter | Type | Description |
|-----------|------|-------------|
| `from` | string | Source file path |
| `to` | string | Destination file path |

**Returns:**
- `success: bool` - Whether the operation succeeded
- `error: string` - Error message if operation failed (optional)

## Behavior

- Parent directories are created automatically if they don't exist
- Existing destination files are overwritten
- File integrity is verified after copy operations
- On Android, if rename fails (cross-filesystem), falls back to copy + delete

## Examples

### Move Recording to Permanent Storage

```php
use Native\Mobile\Facades\File;
use Native\Mobile\Events\Microphone\RecordingFinished;

#[OnNative(RecordingFinished::class)]
public function handleRecording($path, $duration)
{
    $newPath = storage_path("recordings/" . basename($path));

    $result = File::move($path, $newPath);

    if ($result['success']) {
        // Save to database
        Recording::create([
            'path' => $newPath,
            'duration' => $duration
        ]);
    }
}
```

### Backup Photo Before Edit

```php
use Native\Mobile\Facades\File;

public function editPhoto($photoPath)
{
    // Create backup
    $backupPath = str_replace('.jpg', '_backup.jpg', $photoPath);
    File::copy($photoPath, $backupPath);

    // Proceed with editing...
}
```

## License

MIT
