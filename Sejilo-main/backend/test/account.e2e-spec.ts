import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Account & Blocks (e2e, STEP 5/27)', () => {
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
        email: `acc27a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `acc27a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;

    const b = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `acc27b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `acc27b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bob = b.body.token;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('block prevents follow; unblock allows it', async () => {
    // alice blocks bob
    await request(app.getHttpServer())
      .post(`/v1/users/acc27b_${stamp}/block`)
      .set(auth(alice))
      .expect(201);

    // bob tries to follow alice -> forbidden (alice blocked bob)
    await request(app.getHttpServer())
      .post(`/v1/users/acc27a_${stamp}/follow`)
      .set(auth(bob))
      .expect(403);

    // alice unblocks bob
    await request(app.getHttpServer())
      .delete(`/v1/users/acc27b_${stamp}/block`)
      .set(auth(alice))
      .expect(200);

    // now bob can follow
    await request(app.getHttpServer())
      .post(`/v1/users/acc27a_${stamp}/follow`)
      .set(auth(bob))
      .expect(201);
  });

  it('cannot block yourself', async () => {
    await request(app.getHttpServer())
      .post(`/v1/users/acc27a_${stamp}/block`)
      .set(auth(alice))
      .expect(400);
  });

  it('account deletion revokes access', async () => {
    const token = (
      await request(app.getHttpServer())
        .post('/v1/users')
        .send({
          email: `acc27c_${stamp}@test.local`,
          password: 'Str0ngPass!2026',
          username: `acc27c_${stamp}`,
          displayName: 'C',
        })
        .expect(201)
    ).body.token as string;

    await request(app.getHttpServer()).delete('/v1/me').set(auth(token)).expect(204);
    // The JWT strategy validates user existence, so a deleted account -> 401.
    await request(app.getHttpServer()).get('/v1/me').set(auth(token)).expect(401);
  });
});
