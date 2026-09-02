import * as React from 'react';
import { KpiStrip, Kpi } from '@donerup/ui';

export const StoreOperations = () => (
  <KpiStrip>
    <Kpi label="Covers today" value="1,482" />
    <Kpi label="Waste" value="2.8%" />
    <Kpi label="Shift coverage" value="94%" />
    <Kpi label="Reports outstanding" value="3" />
  </KpiStrip>
);
