import * as React from 'react';
import { Kpi } from '@donerup/ui';

export const Single = () => <Kpi label="Covers today" value="1,482" />;

export const Shapes = () => (
  <div style={{ display: 'flex', gap: 14 }}>
    <Kpi label="Waste" value="2.8%" />
    <Kpi label="Reports outstanding" value="3" />
  </div>
);
