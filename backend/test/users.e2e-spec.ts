import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Users & Profiles (e2e)', () => {
  let app: INestApplication;
  let token: string;
  let userId: string;

  const stamp = Date.now();
  const unique = `step7_${stamp}@test.local`;
  const testUsername = `s7_e2e_${stamp}`;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('registers and exercises GET /me, PATCH /me, GET /users/:id, GET /users/:username, GET /users/search', async () => {
    const reg = await request(app.getHttpServer())
      .post('/v1/users')
      .send({ email: unique, password: 'Str0ngPass!2026', username: testUsername, displayName: 'E2E' })
      .expect(201);
    token = reg.body.token;
    userId = reg.body.id;

    const me = await request(app.getHttpServer())
      .get('/v1/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body.profile.username).toBe(testUsername);
    expect(me.body.profile.followersCount).toBe(0);

    const renamed = `s7_renamed_${stamp}`;

    const upd = await request(app.getHttpServer())
      .patch('/v1/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ username: renamed, displayName: 'Renamed' })
      .expect(200);
    expect(upd.body.profile.username).toBe(renamed);

    const byId = await request(app.getHttpServer())
      .get(`/v1/users/${userId}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(byId.body.profile.username).toBe(renamed);

    const byName = await request(app.getHttpServer())
      .get(`/v1/users/${renamed}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(byName.body.profile.displayName).toBe('Renamed');

    const sr = await request(app.getHttpServer())
      .get(`/v1/users/search?q=${renamed}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(sr.body.users.length).toBeGreaterThanOrEqual(1);
  });

  it('rejects unauthenticated access to /v1/me without a token', async () => {
    await request(app.getHttpServer()).get('/v1/me').expect(401);
  });

  describe('STEP 8 — Follow System (e2e)', () => {
    let aliceToken: string;
    let aliceId: string;
    let bobToken: string;
    let bobId: string;

    beforeAll(async () => {
      const stamp8 = Date.now();
      const alice = await request(app.getHttpServer())
        .post('/v1/users')
        .send({
          email: `step8_alice_${stamp8}@test.local`,
          password: 'Str0ngPass!2026',
          username: `s8_alice_${stamp8}`,
          displayName: 'Alice',
        })
        .expect(201);
      aliceToken = alice.body.token;
      aliceId = alice.body.id;

      const bob = await request(app.getHttpServer())
        .post('/v1/users')
        .send({
          email: `step8_bob_${stamp8}@test.local`,
          password: 'Str0ngPass!2026',
          username: `s8_bob_${stamp8}`,
          displayName: 'Bob',
        })
        .expect(201);
      bobToken = bob.body.token;
      bobId = bob.body.id;
    });

    const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

    it('user A follows user B and follower/following lists reflect the edge', async () => {
      const profile = await request(app.getHttpServer())
        .post(`/v1/users/${bobId}/follow`)
        .set(auth(aliceToken))
        .expect(201);
      expect(profile.body.profile.followedByViewer).toBe(true);

      const following = await request(app.getHttpServer())
        .get(`/v1/users/${aliceId}/following`)
        .set(auth(aliceToken))
        .expect(200);
      expect(following.body.users.some((u: any) => u.id === bobId)).toBe(true);

      const followers = await request(app.getHttpServer())
        .get(`/v1/users/${bobId}/followers`)
        .set(auth(bobToken))
        .expect(200);
      expect(followers.body.users.some((u: any) => u.id === aliceId)).toBe(true);
    });

    it('duplicate follow is idempotent (201) and does not double the edge', async () => {
      await request(app.getHttpServer())
        .post(`/v1/users/${bobId}/follow`)
        .set(auth(aliceToken))
        .expect(201);
      const following = await request(app.getHttpServer())
        .get(`/v1/users/${aliceId}/following`)
        .set(auth(aliceToken))
        .expect(200);
      const bobs = following.body.users.filter((u: any) => u.id === bobId);
      expect(bobs.length).toBe(1);
    });

    it('self-follow is rejected with 400', async () => {
      await request(app.getHttpServer())
        .post(`/v1/users/${aliceId}/follow`)
        .set(auth(aliceToken))
        .expect(400);
    });

    it('unfollow removes the edge (410 Gone)', async () => {
      await request(app.getHttpServer())
        .delete(`/v1/users/${bobId}/follow`)
        .set(auth(aliceToken))
        .expect(204);
      const following = await request(app.getHttpServer())
        .get(`/v1/users/${aliceId}/following`)
        .set(auth(aliceToken))
        .expect(200);
      expect(following.body.users.some((u: any) => u.id === bobId)).toBe(false);
    });

    it('unauthenticated follow is rejected with 401', async () => {
      await request(app.getHttpServer())
        .post(`/v1/users/${bobId}/follow`)
        .expect(401);
    });
  });
});
