export const MEMBER_STATUSES = ["ACTIVE", "INACTIVE", "TRANSFERRED", "DECEASED"] as const;
export type MemberStatus = (typeof MEMBER_STATUSES)[number];
