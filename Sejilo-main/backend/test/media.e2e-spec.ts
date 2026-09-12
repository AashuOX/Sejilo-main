import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Media (e2e)', () => {
  let app: INestApplication;
  let alice: string;

  const stamp = Date.now();

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
    );
    await app.init();

    const a = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `m17a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `m17a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('upload-url + fetch metadata + validation/authz', async () => {
    const up = await request(app.getHttpServer())
      .post('/v1/media/upload-url')
      .set(auth(alice))
      .send({ filename: 'pic.jpg', mimeType: 'image/jpeg', sizeBytes: 12345 })
      .expect(201);
    expect(up.body.mediaId).toBeDefined();
    expect(up.body.uploadUrl).toBeDefined();

    const fetched = await request(app.getHttpServer())
      .get(`/v1/media/${up.body.mediaId}`)
      .set(auth(alice))
      .expect(200);
    expect(fetched.body.mimeType).toBe('image/jpeg');

    // nonexistent returns empty body (still 200 with auth)
    const missing = await request(app.getHttpServer())
      .get('/v1/media/00000000-0000-0000-0000-000000000000')
      .set(auth(alice))
      .expect(200);
    expect(missing.body.mimeType).toBeUndefined();

    // unsupported mime -> 400
    await request(app.getHttpServer())
      .post('/v1/media/upload-url')
      .set(auth(alice))
      .send({ filename: 'x.exe', mimeType: 'application/x-msdownload', sizeBytes: 10 })
      .expect(400);

    // authz
    await request(app.getHttpServer())
      .post('/v1/media/upload-url')
      .send({ filename: 'x.jpg', mimeType: 'image/jpeg', sizeBytes: 10 })
      .expect(401);
    await request(app.getHttpServer())
      .get(`/v1/media/${up.body.mediaId}`)
      .expect(401);
  });
});
