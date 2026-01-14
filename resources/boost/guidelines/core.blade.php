## nativephp/file

File operations (move, copy) for NativePHP Mobile applications.

### PHP Usage (Livewire/Blade)

@verbatim
<code-snippet name="Move File" lang="php">
use Native\Mobile\Facades\File;

$success = File::move(
    '/var/mobile/Containers/Data/tmp/photo.jpg',
    '/var/mobile/Containers/Data/Documents/photos/photo.jpg'
);
</code-snippet>
@endverbatim

@verbatim
<code-snippet name="Copy File" lang="php">
use Native\Mobile\Facades\File;

$success = File::copy(
    '/var/mobile/Containers/Data/Documents/document.pdf',
    '/var/mobile/Containers/Data/Documents/backups/document.pdf'
);
</code-snippet>
@endverbatim

### JavaScript Usage (Vue/React/Inertia)

@verbatim
<code-snippet name="File Operations in JavaScript" lang="javascript">
import { file } from '#nativephp';

// Move a file
const moveResult = await file.move(
    '/var/mobile/Containers/Data/tmp/photo.jpg',
    '/var/mobile/Containers/Data/Documents/photos/photo.jpg'
);

// Copy a file
const copyResult = await file.copy(
    '/var/mobile/Containers/Data/Documents/document.pdf',
    '/var/mobile/Containers/Data/Documents/backups/document.pdf'
);
</code-snippet>
@endverbatim

### Methods

- `File::move(string $from, string $to)` - Relocates file, removes original after transfer
- `File::copy(string $from, string $to)` - Duplicates file, preserves original

### Returns

Both methods return boolean (true for success, false for failure).

### Important Notes

- Requires absolute file paths; use Laravel's `storage_path()` helper
- Source file and destination directory must exist and be accessible
- Returns false if source doesn't exist or destination already exists
- Operations execute synchronously and block until completion
- No events dispatched; results returned directly
