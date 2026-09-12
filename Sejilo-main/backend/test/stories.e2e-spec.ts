import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Stories (e2e)', () => {
  let app: INestApplication;
  let alice: string;
  let bob: string;

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
        email: `s9a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `s9a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;

    const b = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `s9b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `s9b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bob = b.body.token;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('creates a text story expiring ~24h ahead', async () => {
    const res = await request(app.getHttpServer())
      .post('/v1/stories')
      .set(auth(alice))
      .send({ type: 'text', textContent: 'hi', backgroundStyle: 'gradient_0' })
      .expect(201);
    expect(res.body.id).toBeTruthy();
    expect(res.body.expiresAt).toBeTruthy();
    const exp = new Date(res.body.expiresAt).getTime();
    expect(exp - Date.now()).toBeGreaterThan(23 * 60 * 60 * 1000);
  });

  it('validation rejects missing type (400)', async () => {
    await request(app.getHttpServer())
      .post('/v1/stories')
      .set(auth(alice))
      .send({ textContent: 'no type' })
      .expect(400);
  });

  it('unauthenticated access is 401', async () => {
    await request(app.getHttpServer()).get('/v1/stories').expect(401);
    await request(app.getHttpServer())
      .post('/v1/stories')
      .send({ type: 'text' })
      .expect(401);
  });

  it('follower sees story after follow; non-owner cannot read viewers', async () => {
    // capture alice's username via /me
    const me = await request(app.getHttpServer())
      .get('/v1/me')
      .set(auth(alice))
      .expect(200);
    const aliceName = me.body.profile.username as string;

    await request(app.getHttpServer())
      .post(`/v1/users/${aliceName}/follow`)
      .set(auth(bob))
      .expect(201);

    const res = await request(app.getHttpServer())
      .get('/v1/stories')
      .set(auth(bob))
      .expect(200);
    expect(res.body.stories.length).toBeGreaterThanOrEqual(1);

    const storyId = res.body.stories[0].id as string;
    // viewer marks viewed
    await request(app.getHttpServer())
      .post(`/v1/stories/${storyId}/views`)
      .set(auth(bob))
      .expect(204);
    // non-owner (bob) cannot read alice's viewers
    await request(app.getHttpServer())
      .get(`/v1/stories/${storyId}/views`)
      .set(auth(bob))
      .expect(403);
    // owner (alice) can read viewers
    const viewers = await request(app.getHttpServer())
      .get(`/v1/stories/${storyId}/views`)
      .set(auth(alice))
      .expect(200);
    expect(viewers.body.viewers.length).toBe(1);
  });

  it('delete own story 204; delete other 403; not found 404', async () => {
    const created = await request(app.getHttpServer())
      .post('/v1/stories')
      .set(auth(alice))
      .send({ type: 'text', textContent: 'to delete' })
      .expect(201);
    const sid = created.body.id;

    await request(app.getHttpServer())
      .delete(`/v1/stories/${sid}`)
      .set(auth(alice))
      .expect(204);

    await request(app.getHttpServer())
      .delete('/v1/stories/00000000-0000-0000-0000-000000000000')
      .set(auth(alice))
      .expect(404);

    // create a second story as alice, bob tries to delete => 403
    const other = await request(app.getHttpServer())
      .post('/v1/stories')
      .set(auth(alice))
      .send({ type: 'text', textContent: 'dont delete' })
      .expect(201);
    await request(app.getHttpServer())
      .delete(`/v1/stories/${other.body.id}`)
      .set(auth(bob))
      .expect(403);
  });
});
