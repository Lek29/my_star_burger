from django.contrib import admin

from .models import GeocodedAddress


@admin.register(GeocodedAddress)
class GeocodedAddressAdmin(admin.ModelAdmin):
    list_display = ('address', 'latitude', 'longitude', 'queried_at')
    search_fields = ('address',)
    list_filter = ('queried_at',)
    readonly_fields = ('queried_at',)
