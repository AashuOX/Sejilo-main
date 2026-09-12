import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateReportDto } from './dto/create-report.dto';

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type ReportRow = {
  id: string;
  targetType: string;
  targetId: string;
  reason: string;
  details: string | null;
  status: string;
  createdAt: Date;
  resolvedAt: Date | null;
};

/**
 * Writes and reads rows of the `reports` table.
 *
 * The table shipped in the initial migration but had no routes, so the app's
 * report buttons were posting into a 404 — this service is the missing half.
 * Reports are recorded, not acted on: there is no moderator tooling in this
 * deployment, so the only reader is the reporter's own history screen.
 */
@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async reportUser(reporterId: string, identifier: string, dto: CreateReportDto) {
    const trimmed = identifier.trim();
    const target = UUID_PATTERN.test(trimmed)
      ? await this.prisma.user.findUnique({ where: { id: trimmed }, select: { id: true } })
      : await this.prisma.user.findFirst({
          where: { profile: { username: trimmed.toLowerCase() } },
          select: { id: true },
        });
    if (!target) throw new NotFoundException('User to report not found.');
    if (target.id === reporterId) throw new BadRequestException('You cannot report yourself.');
    return this.create(reporterId, 'user', target.id, dto);
  }

  async reportPost(reporterId: string, postId: string, dto: CreateReportDto) {
    const trimmed = postId.trim();
    // targetId is a uuid column, so a junk id has to be refused here rather than
    // handed to Postgres as a cast error.
    if (!UUID_PATTERN.test(trimmed)) {
      throw new BadRequestException('Post id must be a uuid.');
    }
    const post = await this.prisma.post.findFirst({
      where: { id: trimmed, deletedAt: null },
      select: { id: true, userId: true },
    });
    if (!post) throw new NotFoundException('Post to report not found.');
    if (post.userId === reporterId) {
      throw new BadRequestException('You cannot report your own post.');
    }
    return this.create(reporterId, 'post', post.id, dto);
  }

  /**
   * The reports this account has filed, newest first.
   *
   * Only ever the caller's own rows: a report names the person who filed it, so
   * exposing anyone else's would tell a reported user who turned them in.
   */
  async listMyReports(reporterId: string, limit: number) {
    const reports = await this.prisma.report.findMany({
      where: { reporterId },
      orderBy: { createdAt: 'desc' },
      take: Math.min(Math.max(limit, 1), 100),
      select: {
        id: true,
        targetType: true,
        targetId: true,
        reason: true,
        details: true,
        status: true,
        createdAt: true,
        resolvedAt: true,
      },
    });
    return { reports: await this.hydrate(reports) };
  }

  private async create(
    reporterId: string,
    targetType: 'user' | 'post',
    targetId: string,
    dto: CreateReportDto,
  ) {
    // Re-reporting the same target updates the open row instead of stacking
    // duplicates — tapping twice is a slip, not two complaints.
    const open = await this.prisma.report.findFirst({
      where: { reporterId, targetType, targetId, status: 'pending' },
      select: { id: true },
    });
    const data = {
      reason: dto.reason.trim(),
      details: dto.details?.trim() ? dto.details.trim() : null,
    };
    const report = open
      ? await this.prisma.report.update({ where: { id: open.id }, data })
      : await this.prisma.report.create({
          data: { reporterId, targetType, targetId, ...data },
        });
    return { report: this.serialize(report) };
  }

  /**
   * Attaches a short label for each target so the history screen can say what
   * was reported instead of showing a bare uuid.
   *
   * Two batched queries regardless of how many reports come back. A target that
   * has since been deleted simply has no label.
   */
  private async hydrate(reports: ReportRow[]) {
    const userIds = reports.filter((r) => r.targetType === 'user').map((r) => r.targetId);
    const postIds = reports.filter((r) => r.targetType === 'post').map((r) => r.targetId);

    const [profiles, posts] = await Promise.all([
      userIds.length
        ? this.prisma.profile.findMany({
            where: { userId: { in: userIds } },
            select: { userId: true, username: true, displayName: true },
          })
        : Promise.resolve([]),
      postIds.length
        ? this.prisma.post.findMany({
            where: { id: { in: postIds } },
            select: { id: true, caption: true, deletedAt: true },
          })
        : Promise.resolve([]),
    ]);

    const profileById = new Map(profiles.map((p) => [p.userId, p]));
    const postById = new Map(posts.map((p) => [p.id, p]));

    return reports.map((report) => {
      const base = this.serialize(report);
      if (report.targetType === 'user') {
        const profile = profileById.get(report.targetId);
        return {
          ...base,
          targetLabel: profile ? `@${profile.username}` : null,
          targetName: profile?.displayName ?? null,
        };
      }
      const post = postById.get(report.targetId);
      return {
        ...base,
        targetLabel: post ? (post.caption?.trim() || 'Photo post') : null,
        targetName: null,
        targetDeleted: post ? post.deletedAt !== null : true,
      };
    });
  }

  private serialize(report: ReportRow) {
    return {
      id: report.id,
      targetType: report.targetType,
      targetId: report.targetId,
      reason: report.reason,
      details: report.details,
      status: report.status,
      createdAt: report.createdAt.toISOString(),
      resolvedAt: report.resolvedAt?.toISOString() ?? null,
    };
  }
}
