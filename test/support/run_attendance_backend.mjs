import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';

// Bootstrap only a fresh in-memory database. Provision fixtures through REST.
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
async function api(path, method, body, token) {
  const response = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
  if (!response.ok) throw new Error(`Fixture setup ${path}: HTTP ${response.status}`);
  return response.json();
}
try {
  const admin = await api('/auth/login', 'POST', { email: process.env.HR_ADMIN_EMAIL, password: process.env.HR_ADMIN_PASSWORD });
  const [schedule] = await api('/schedules', 'GET', null, admin.token);
  await api('/employees', 'POST', { nationalId: '00123456789012', name: 'Isolated Mobile Employee',
    email: 'mobile-employee@example.test', department: 'Engineering', jobTitle: 'Test fixture',
    startDate: '2026-01-01', scheduleId: schedule.id, active: true, role: 'employee',
    password: 'Isolated-employee-password-2026' }, admin.token);
  const command = `flutter test test/attendance_backend_test.dart --dart-define=ATTENDANCE_TEST_API=${base}`;
  const child = process.platform === 'win32'
    ? spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', command], { stdio: 'inherit' })
    : spawn('flutter', ['test', 'test/attendance_backend_test.dart', `--dart-define=ATTENDANCE_TEST_API=${base}`], { stdio: 'inherit' });
  process.exitCode = await new Promise((resolveExit, reject) => { child.on('exit', resolveExit); child.on('error', reject); });
} finally { await app.close(); }
