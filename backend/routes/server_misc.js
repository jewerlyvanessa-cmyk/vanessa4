'use strict';

function registerServerMiscRoutes(app, deps) {
  const { db, upload } = deps;

  app.get('/upload', (req, res) => {
    res.send('Gunakan POST untuk upload file ke endpoint ini.');
  });

  /** Upload foto (field: `file`) — mengembalikan path `/uploads/<filename>`. */
  app.post('/upload', upload.any(), async (req, res) => {
    try {
      const file =
        Array.isArray(req.files) && req.files.length > 0 ? req.files[0] : req.file;

      if (!file) {
        return res.status(400).json({ error: 'No file uploaded' });
      }

      const urlPath = `/uploads/${file.filename}`;

      try {
        await db.query(
          `INSERT INTO uploads (storage_key, original_name, mime_type, size_bytes, url_path, uploaded_by_user_id)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [
            file.filename,
            file.originalname || null,
            file.mimetype || null,
            typeof file.size === 'number' ? file.size : null,
            urlPath,
            null,
          ]
        );
      } catch (_) {
        // ignore if uploads table doesn't exist or insert fails
      }

      res.status(200).json({
        success: true,
        url: urlPath,
        fileUrl: urlPath,
        path: urlPath,
        filename: file.filename,
      });
    } catch (error) {
      console.error('Error uploading file:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  app.get('/', (req, res) => {
    res.send('Server is running!');
  });

  app.get('/test-db', async (req, res) => {
    try {
      const result = await db.query('SELECT NOW()');
      res.status(200).json({
        message: 'Database connected successfully',
        time: result.rows[0].now,
      });
    } catch (error) {
      console.error('Database connection error:', error);
      res.status(500).json({ error: 'Database connection failed' });
    }
  });
}

module.exports = { registerServerMiscRoutes };
