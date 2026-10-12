import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';

// Only bootstrap a fresh in-memory database; never attach to company data.
const backend = resolve(process.argv[2]);
process.env.HR_DATABASE_PATH = ':memory:';
process.env.HR_ADMIN_EMAIL = 'admin@example.test';
process.env.HR_ADMIN_PASSWORD = 'Isolated-admin-password-2026';
const { NestFactory } = await import(pathToFileURL(join(backend, 'node_modules/@nestjs/core/index.js')));
const { AppModule } = await import(pathToFileURL(join(backend, 'dist/app.module.js')));
const app = await NestFactory.create(AppModule, { logger: false });
app.useBodyParser('json', { limit: '3mb' });
await app.listen(0, '127.0.0.1');
const base = `${await app.getUrl()}/api`;
try {
  const command = `flutter test test/sales_backend_test.dart --dart-define=SALES_TEST_API=${base}`;
  const child = process.platform === 'win32'
    ? spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', command], { stdio: 'inherit' })
    : spawn('flutter', ['test', 'test/sales_backend_test.dart', `--dart-define=SALES_TEST_API=${base}`], { stdio: 'inherit' });
  process.exitCode = await new Promise((resolveExit, reject) => { child.on('exit', resolveExit); child.on('error', reject); });
} finally { await app.close(); }
