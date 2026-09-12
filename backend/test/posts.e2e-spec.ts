import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Posts, Likes & Comments (e2e)', () => {
  let app: INestApplication;
  let alice: string;
  let bob: string;

  const stamp = Date.now();
  const imgData = Buffer.from('test-image-bytes').toString('base64url');

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
        email: `p10a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `p10a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;

    const b = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `p10b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `p10b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bob = b.body.token;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('creates a post, appears in feed, like/unlike flow', async () => {
    const created = await request(app.getHttpServer())
      .post('/v1/posts')
      .set(auth(alice))
      .send({ media: { mimeType: 'image/jpeg', data: imgData }, caption: 'hi' })
      .expect(201);
    const pid = created.body.id as string;
    expect(pid).toBeTruthy();

    const feed = await request(app.getHttpServer())
      .get('/v1/feed')
      .set(auth(alice))
      .expect(200);
    expect(feed.body.posts.some((p: any) => p.id === pid)).toBe(true);

    await request(app.getHttpServer())
      .post(`/v1/posts/${pid}/likes`)
      .set(auth(alice))
      .expect(204);
    const feedLiked = await request(app.getHttpServer())
      .get('/v1/feed')
      .set(auth(alice))
      .expect(200);
    const post = feedLiked.body.posts.find((p: any) => p.id === pid);
    expect(post.liked).toBe(true);
    expect(post.likes).toBe(1);

    await request(app.getHttpServer())
      .delete(`/v1/posts/${pid}/likes`)
      .set(auth(alice))
      .expect(204);
  });

  it('comments: add, list, delete own; delete other post is 403', async () => {
    const created = await request(app.getHttpServer())
      .post('/v1/posts')
      .set(auth(alice))
      .send({ media: { mimeType: 'image/jpeg', data: imgData }, caption: 'c' })
      .expect(201);
    const pid = created.body.id as string;

    const cm = await request(app.getHttpServer())
      .post(`/v1/posts/${pid}/comments`)
      .set(auth(bob))
      .send({ text: 'nice' })
      .expect(201);
    const cid = cm.body.id as string;
    expect(cid).toBeTruthy();

    const list = await request(app.getHttpServer())
      .get(`/v1/posts/${pid}/comments`)
      .expect(200);
    expect(list.body.comments.some((c: any) => c.id === cid)).toBe(true);

    await request(app.getHttpServer())
      .delete(`/v1/comments/${cid}`)
      .set(auth(bob))
      .expect(204);

    await request(app.getHttpServer())
      .delete(`/v1/posts/${pid}`)
      .set(auth(bob))
      .expect(403);

    await request(app.getHttpServer())
      .delete(`/v1/posts/${pid}`)
      .set(auth(alice))
      .expect(204);
  });

  it('validation + authz: missing media 400, unauth create 401, not-found delete 404', async () => {
    await request(app.getHttpServer())
      .post('/v1/posts')
      .set(auth(alice))
      .send({ caption: 'no media' })
      .expect(400);
    await request(app.getHttpServer())
      .post('/v1/posts')
      .send({ media: { mimeType: 'image/jpeg', data: imgData } })
      .expect(401);
    await request(app.getHttpServer())
      .delete('/v1/posts/00000000-0000-0000-0000-000000000000')
      .set(auth(alice))
      .expect(404);
  });
});
