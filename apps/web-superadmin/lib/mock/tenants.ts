export type TenantStatus = "Trial" | "Active" | "Past Due" | "Suspended" | "Cancelled";

export type TenantRow = {
  id: string;
  name: string;
  plan: "Trial" | "Basic" | "Pro" | "Enterprise";
  status: TenantStatus;
  seatsUsed: number;
  seatsLimit: number;
  lastActivityISO: string;
};

export const mockTenants: TenantRow[] = [
  {
    id: "tnt_001",
    name: "Grace Chapel International",
    plan: "Pro",
    status: "Active",
    seatsUsed: 12,
    seatsLimit: 15,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 18).toISOString()
  },
  {
    id: "tnt_002",
    name: "House of Prayer Ministries",
    plan: "Basic",
    status: "Past Due",
    seatsUsed: 4,
    seatsLimit: 5,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 60 * 26).toISOString()
  },
  {
    id: "tnt_003",
    name: "New Dawn Assembly",
    plan: "Trial",
    status: "Trial",
    seatsUsed: 2,
    seatsLimit: 3,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 60 * 6).toISOString()
  },
  {
    id: "tnt_004",
    name: "Living Waters Church",
    plan: "Pro",
    status: "Suspended",
    seatsUsed: 9,
    seatsLimit: 15,
    lastActivityISO: new Date(Date.now() - 1000 * 60 * 60 * 72).toISOString()
  }
];
