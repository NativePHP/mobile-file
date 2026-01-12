## nativephp/file

File operations (move, copy) for NativePHP Mobile applications.

### Installation

```bash
composer require nativephp/file
php artisan native:plugin:register nativephp/file
```

### PHP Usage (Livewire/Blade)

Use the `File` facade:

@verbatim
<code-snippet name="File Operations" lang="php">
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
</code-snippet>
@endverbatim

@verbatim
<code-snippet name="Moving Recordings to Storage" lang="php">
use Native\Mobile\Facades\File;
use Native\Mobile\Events\Microphone\RecordingFinished;

#[OnNative(RecordingFinished::class)]
public function handleRecording($path, $duration)
{
    $newPath = storage_path("recordings/" . basename($path));

    $result = File::move($path, $newPath);

    if ($result['success']) {
        Recording::create([
            'path' => $newPath,
            'duration' => $duration
        ]);
    }
}
</code-snippet>
@endverbatim

### JavaScript Usage

@verbatim
<code-snippet name="File Operations in JavaScript" lang="js">
import { file } from '#nativephp';

// Move a file
const moveResult = await file.move('/path/to/source.txt', '/path/to/destination.txt');

if (moveResult.success) {
    console.log('File moved successfully!');
}

// Copy a file
const copyResult = await file.copy('/path/to/source.txt', '/path/to/copy.txt');

if (copyResult.success) {
    console.log('File copied successfully!');
}
</code-snippet>
@endverbatim

### Available Methods

- `File::move(string $from, string $to)` - Move file from source to destination
- `File::copy(string $from, string $to)` - Copy file from source to destination

### Return Values

Both methods return an array:
- `success: bool` - Whether the operation succeeded
- `error: string` - Error message if operation failed (optional)

### Behavior

- Parent directories are created automatically if they don't exist
- Existing destination files are overwritten
- File integrity is verified after copy operations
- On Android, if rename fails (cross-filesystem), falls back to copy + delete

### Platform Details

- **iOS**: Uses FileManager for all operations
- **Android**: Uses Java File API with automatic directory creation