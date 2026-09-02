import * as React from 'react';
import { ReportTextarea } from '@donerup/ui';

export const WithTemplate = () => (
  <ReportTextarea
    defaultValue={`Donerup — Weekly Store Report
Site: {{ site.code }} {{ site.name }}
Period: week {{ period.week }} ({{ period.start }} to {{ period.end }})

Covers          {{ metrics.covers }}
Waste           {{ metrics.waste_pct }}%
Shift coverage  {{ metrics.coverage_pct }}%

Prepared by {{ user.display_name }}, {{ site.region }}`}
  />
);

export const Empty = () => (
  <ReportTextarea placeholder="Paste or edit the store report template…" />
);
