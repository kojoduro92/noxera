/**
 * Permission keys follow the blueprint:
 * module.action.scope (e.g., members.view.any)
 */
export const PERMISSIONS = {
  // Members
  MEMBERS_VIEW_ANY: "members.view.any",
  MEMBERS_EDIT_ANY: "members.edit.any",
  MEMBERS_EXPORT_ANY: "members.export.any",

  // Attendance
  ATTENDANCE_CHECKIN: "attendance.checkin",
  ATTENDANCE_REPORTS_VIEW: "attendance.reports.view",

  // Giving
  GIVING_CREATE: "giving.create",
  GIVING_APPROVE: "giving.approve",
  GIVING_EXPORT: "giving.export",

  // Website
  WEBSITE_PAGES_EDIT: "website.pages.edit",
  WEBSITE_PUBLISH: "website.publish",
  WEBSITE_DOMAINS_MANAGE: "website.domains.manage",

  // Super Admin
  ADMIN_IMPERSONATE: "admin.impersonate"
} as const;

export type PermissionKey = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];
