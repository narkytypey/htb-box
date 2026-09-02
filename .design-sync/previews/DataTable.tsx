import * as React from 'react';
import { DataTable } from '@donerup/ui';

export const SitesReporting = () => (
  <DataTable
    columns={[
      { key: 'code', label: 'Code' },
      { key: 'site', label: 'Site' },
      { key: 'region', label: 'Region' },
      { key: 'manager', label: 'Manager' },
    ]}
    rows={[
      { code: 'DNR-001', site: 'Berlin Mitte', region: 'DACH', manager: 'Emre Arslan' },
      { code: 'DNR-004', site: 'Hamburg St Pauli', region: 'DACH', manager: '— vacant' },
      { code: 'DNR-014', site: 'Hamburg Altona', region: 'DACH', manager: 'Jonas Becker' },
      { code: 'DNR-022', site: 'London Dalston', region: 'UK&I', manager: 'Fatma Cetin' },
      { code: 'DNR-027', site: 'London Peckham', region: 'UK&I', manager: 'Michael Okonkwo' },
      { code: 'DNR-031', site: 'Rotterdam Centrum', region: 'Benelux', manager: 'Sanne Bakker' },
    ]}
  />
);

export const RecentReports = () => (
  <DataTable
    columns={[
      { key: 'period', label: 'Period' },
      { key: 'site', label: 'Site' },
      { key: 'submitted', label: 'Submitted' },
    ]}
    rows={[
      { period: 'Week 33', site: 'DNR-001', submitted: '2026-08-18' },
      { period: 'Week 33', site: 'DNR-022', submitted: '2026-08-18' },
      { period: 'Week 33', site: 'DNR-014', submitted: '2026-08-19' },
      { period: 'Week 32', site: 'DNR-031', submitted: '2026-08-11' },
    ]}
  />
);
