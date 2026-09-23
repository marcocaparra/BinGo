import { AfterViewInit, ChangeDetectionStrategy, Component, ElementRef, ViewChild } from '@angular/core';
import { mountAdmin } from './admin-legacy';

@Component({
  selector: 'app-root',
  template: '<div #adminRoot id="admin-root" aria-live="polite"></div>',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class App implements AfterViewInit {
  @ViewChild('adminRoot', { static: true }) adminRoot!: ElementRef<HTMLElement>;

  ngAfterViewInit(): void {
    mountAdmin(this.adminRoot.nativeElement);
  }
}
