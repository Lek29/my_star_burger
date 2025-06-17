from django.contrib import admin
from django.shortcuts import reverse, redirect
from django.templatetags.static import static
from django.utils.html import format_html
from django.db.models import Prefetch
from django.utils.http import url_has_allowed_host_and_scheme

from .models import Product
from .models import ProductCategory
from .models import Restaurant
from .models import RestaurantMenuItem
from .models import Order
from .models import OrderItem


class RestaurantMenuItemInline(admin.TabularInline):
    model = RestaurantMenuItem
    extra = 0


@admin.register(Restaurant)
class RestaurantAdmin(admin.ModelAdmin):
    search_fields = [
        'name',
        'address',
        'contact_phone',
    ]
    list_display = [
        'name',
        'address',
        'contact_phone',
    ]
    inlines = [
        RestaurantMenuItemInline
    ]


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = [
        'get_image_list_preview',
        'name',
        'category',
        'price',
    ]
    list_display_links = [
        'name',
    ]
    list_filter = [
        'category',
    ]
    search_fields = [
        # FIXME SQLite can not convert letter case for cyrillic words properly, so search will be buggy.
        # Migration to PostgreSQL is necessary
        'name',
        'category__name',
    ]

    inlines = [
        RestaurantMenuItemInline
    ]
    fieldsets = (
        ('Общее', {
            'fields': [
                'name',
                'category',
                'image',
                'get_image_preview',
                'price',
            ]
        }),
        ('Подробно', {
            'fields': [
                'special_status',
                'description',
            ],
            'classes': [
                'wide'
            ],
        }),
    )

    readonly_fields = [
        'get_image_preview',
    ]

    class Media:
        css = {
            "all": (
                static("admin/foodcartapp.css")
            )
        }

    def get_image_preview(self, obj):
        if not obj.image:
            return 'выберите картинку'
        return format_html('<img src="{url}" style="max-height: 200px;"/>', url=obj.image.url)
    get_image_preview.short_description = 'превью'

    def get_image_list_preview(self, obj):
        if not obj.image or not obj.id:
            return 'нет картинки'
        edit_url = reverse('admin:foodcartapp_product_change', args=(obj.id,))
        return format_html('<a href="{edit_url}"><img src="{src}" style="max-height: 50px;"/></a>', edit_url=edit_url, src=obj.image.url)
    get_image_list_preview.short_description = 'превью'


@admin.register(ProductCategory)
class ProductCategoryAdmin(admin.ModelAdmin):
    pass


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    fields = ['product', 'quantity', 'price_at_purchase']
    readonly_fields = ['price_at_purchase']
    extra = 0


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'client_name',
        'surname',
        'phone',
        'delivery_address',
        'created_at',
        'restaurant',
        'status',
        'payment_method',
    )

    search_fields = (
        'id',
        'client_name',
        'surname',
        'phone',
        'delivery_address',
        'items__product__name',
        'restaurant__name',
    )
    fields = (
        'client_name', 'phone', 'delivery_address', 'status',
        'payment_method', 'customer_comment',
        'restaurant',
        'called_at',
        'delivered_at',
    )
    readonly_fields = ('created_at',)

    inlines = [
        OrderItemInline,
    ]


    def get_form(self, request, obj=None, **kwargs):
        if obj:
            obj = Order.objects.prefetch_available_restaurants().get(pk=obj.pk)
        self.obj = obj
        return super().get_form(request, obj, **kwargs)


    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "restaurant":
            if self.obj:
                suitable_restaurants = Order.objects.get_matching_restaurants_for_order(self.obj)

                kwargs["queryset"] = Restaurant.objects.filter(id__in=[r.id for r in suitable_restaurants])
            else:
                kwargs["queryset"] = Restaurant.objects.all()
        return super().formfield_for_foreignkey(db_field, request, **kwargs)


    def save_model(self, request, obj, form, change):
        if not change and not obj.restaurant:
            obj.status = Order.STATUS_NEW
        elif 'restaurant' in form.changed_data and obj.restaurant:
            obj.status = Order.STATUS_PREPARING

        super().save_model(request, obj, form, change)



    def save_formset(self, request, form, formset, change):
        instances = formset.save(commit=False)
        for instance in instances:
            if isinstance(instance, OrderItem) and not instance.pk and instance.product:
                instance.price_at_purchase = instance.product.price
            instance.save()
        formset.save_m2m()


    def response_change(self, request, obj):

        if "_save" in request.POST or "_continue" in request.POST:

            return redirect(reverse('restaurateur:view_orders'))
        return super().response_change(request, obj)


    def response_add(self, request, obj, post_url_continue=None):
        if "_save" in request.POST or "_continue" in request.POST:
            redirect_url = reverse('restaurateur:view_orders')
            return redirect(redirect_url)
        return super().response_add(request, obj, post_url_continue)
