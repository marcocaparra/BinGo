import { ChangeDetectionStrategy, Component, inject, input } from '@angular/core';
import { AdminView } from '../admin-access';
import { AdminStore } from '../core/admin-store';
import { DepositsComponent, HelpComponent } from '../features/activity.component';
import { MachinesComponent } from '../features/machines.component';
import {
  AdministratorsComponent,
  ClassesComponent,
  EconomyComponent,
  MissionsComponent,
  PendingComponent,
  ProductsComponent,
  RequestsComponent,
  SchoolsComponent,
  StudentsComponent,
} from '../features/management.component';
import { OverviewComponent } from '../features/overview.component';
import { RedemptionsComponent } from '../features/redemptions.component';
@Component({
  selector: 'app-admin-a',
  imports: [
    OverviewComponent,
    SchoolsComponent,
    AdministratorsComponent,
    MachinesComponent,
    MissionsComponent,
    EconomyComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@switch (view()) {
    @case ('schools') {
      <app-schools />
    }
    @case ('administrators') {
      <app-administrators role="ADMIN_A" />
    }
    @case ('machines') {
      <app-machines />
    }
    @case ('missions') {
      <app-missions role="ADMIN_A" />
    }
    @case ('economy') {
      <app-economy />
    }
    @default {
      <app-overview role="ADMIN_A" />
    }
  }`,
})
export class AdminAComponent {
  view = input.required<AdminView>();
}
@Component({
  selector: 'app-admin-b',
  imports: [
    OverviewComponent,
    StudentsComponent,
    ClassesComponent,
    AdministratorsComponent,
    PendingComponent,
    DepositsComponent,
    HelpComponent,
    ProductsComponent,
    RedemptionsComponent,
    MissionsComponent,
    MachinesComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@switch (view()) {
    @case ('students') {
      <app-students role="ADMIN_B" />
    }
    @case ('classes') {
      <app-classes />
    }
    @case ('administrators') {
      <app-administrators role="ADMIN_B" />
    }
    @case ('pending') {
      <app-pending />
    }
    @case ('deposits') {
      <app-deposits />
    }
    @case ('help') {
      <app-help />
    }
    @case ('products') {
      <app-products />
    }
    @case ('redemptions') {
      <app-redemptions />
    }
    @case ('missions') {
      <app-missions role="ADMIN_B" />
    }
    @case ('machines') {
      <app-machines />
    }
    @default {
      <app-overview role="ADMIN_B" />
    }
  }`,
})
export class AdminBComponent {
  view = input.required<AdminView>();
}
@Component({
  selector: 'app-admin-c',
  imports: [
    OverviewComponent,
    StudentsComponent,
    RequestsComponent,
    DepositsComponent,
    HelpComponent,
    ProductsComponent,
    RedemptionsComponent,
    MachinesComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `@switch (view()) {
    @case ('students') {
      <app-students role="ADMIN_C" />
    }
    @case ('requests') {
      <app-requests />
    }
    @case ('deposits') {
      <app-deposits />
    }
    @case ('help') {
      <app-help />
    }
    @case ('products') {
      <app-products />
    }
    @case ('redemptions') {
      <app-redemptions />
    }
    @case ('machines') {
      <app-machines />
    }
    @default {
      <app-overview role="ADMIN_C" />
    }
  }`,
})
export class AdminCComponent {
  view = input.required<AdminView>();
}
